// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { TokenAdminRegistry } from "@chainlink/contracts-ccip/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IOwner } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IOwner.sol";
import { IGetCCIPAdmin } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IGetCCIPAdmin.sol";
import { RegistryModuleOwnerCustom } from
  "@chainlink/contracts-ccip/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import { BurnMintERC677 } from "@chainlink/contracts-ccip/src/v0.8/shared/token/ERC677/BurnMintERC677.sol";
import { CCIPReceiver, Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ITokensManager } from "./interfaces/ITokensManager.sol";

contract TokensManager is AccessControlEnumerable, CCIPReceiver, Initializable, ITokensManager {
  using EnumerableSet for EnumerableSet.AddressSet;

  uint64 internal immutable _thisChainSelector;
  address[] internal _tokens;
  /// @dev A mapping of tokens to their remote token addresses on different chains.
  mapping(address token => mapping(uint64 chainSelector => address remoteToken)) internal _remoteTokens;
  /// @dev A mapping of deployed tokens to their deployers.
  mapping(address deployedToken => address deployer) internal _tokenDeployers;
  /// @dev A mapping of deployers to the tokens they have deployed.
  mapping(address deployer => address[] tokensDeployed) internal _deployerTokens;
  /// @dev A mapping of chain selectors to the remote tokens managers.
  mapping(uint64 chainSelector => address remoteTokensManager) internal _remoteTokensManagers;
  /// @dev A mapping of chain selectors to the callback gas limits.
  mapping(uint64 chainSelector => uint256 callBackGasLimit) internal _callBackGasLimits;
  /// @dev The address of the concentrated pool.
  address internal _concentratedPool;
  /// @dev The address of the LINK token.
  address internal _link;
  /// @dev The address of the token admin registry.
  TokenAdminRegistry internal _tokenAdminRegistry;
  /// @dev The address of the registry module owner custom.
  RegistryModuleOwnerCustom internal _registryModuleOwnerCustom;
  /// @dev Indicates whether the contract will pay for the CCIP messages.
  bool internal _sponsored;
  EnumerableSet.AddressSet internal _deployedTokens;

  receive() external payable { }
  fallback() external payable { }

  constructor(address ccipRouter, uint64 chainSelector) CCIPReceiver(ccipRouter) {
    _thisChainSelector = chainSelector;
    // _disableInitializers();
  }

  function initialize(
    address admin,
    address tokenAdminRegistry,
    address concentratedPool,
    address registryModuleOwnerCustom,
    address link
  ) external initializer {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _setTokenAdminRegistry(tokenAdminRegistry);
    _setConcentratedPool(concentratedPool);
    _setRegistryModuleOwnerCustom(registryModuleOwnerCustom);
    _setLinkToken(link);
  }

  /// @inheritdoc ITokensManager
  function createTokenUnderManagement(
    TokenInfo calldata tokenInfo,
    uint64 destinationChainSelector,
    bool payWithNative
  ) external payable returns (address) {
    // Deploy the token with create2 to make sure the token address deployed by the same deployer is the same on all chains
    bytes32 salt = keccak256(
      abi.encodePacked(
        tokenInfo.name,
        tokenInfo.symbol,
        tokenInfo.decimals,
        tokenInfo.initialSupply,
        _deployerTokens[msg.sender].length
      )
    );
    BurnMintERC677 token =
      new BurnMintERC677{ salt: salt }(tokenInfo.name, tokenInfo.symbol, tokenInfo.decimals, tokenInfo.initialSupply);
    // Update state
    _deployerTokens[msg.sender].push(address(token));
    _tokenDeployers[address(token)] = msg.sender;
    _mintTokenForDeployer(token, tokenInfo.mintAmount, msg.sender);
    _deployedTokens.add(address(token));
    _remoteTokens[address(token)][destinationChainSelector] = address(token);
    // Grant roles to the concentrated pool
    token.grantMintAndBurnRoles(_concentratedPool);
    // Register the token
    _registryToken(address(token), true);
    _setPoolForToken(address(token));
    // Transfer ownership back to the deployer.
    token.transferOwnership(msg.sender);
    // Create a CCIP message to create the token on the destination chain
    Client.EVM2AnyMessage memory message = _buildCCIPMessage(tokenInfo, destinationChainSelector, payWithNative);
    uint256 fees = IRouterClient(i_ccipRouter).getFee(destinationChainSelector, message);
    bytes32 messageId;
    // Send the CCIP message
    if (_sponsored) {
      _sendSponsoredMessage(destinationChainSelector, message, fees, payWithNative);
    } else {
      _sendUnsponsoredMessage(destinationChainSelector, message, fees, payWithNative);
    }
    emit TokenCreated(_thisChainSelector, address(token), msg.sender, tokenInfo, messageId);
    return address(token);
  }

  /// @inheritdoc ITokensManager
  function setCallBackGasLimit(uint64 chainSelector, uint256 gasLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _callBackGasLimits[chainSelector] = gasLimit;
    emit CallBackGasLimitSet(chainSelector, gasLimit);
  }

  /// @inheritdoc ITokensManager
  function setRemoteTokensManager(
    uint64 chainSelector,
    address remoteTokensManager
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setRemoteTokensManager(chainSelector, remoteTokensManager);
  }

  /// @inheritdoc ITokensManager
  function setConcentratedPool(
    address concentratedPool
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setConcentratedPool(concentratedPool);
  }

  /// @inheritdoc ITokensManager
  function setSponsored(
    bool sponsored
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _sponsored = sponsored;
    emit SponsoredSet(sponsored);
  }

  /// @inheritdoc ITokensManager
  function removeToken(
    address token
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _deployedTokens.remove(token);
    emit TokenRemoved(token);
  }

  function getFee(TokenInfo memory token, uint64 chainSelector) external view returns (uint256 fee) { }

  /// @inheritdoc ITokensManager
  function getManagedTokens() external view returns (address[] memory) {
    return _deployedTokens.values();
  }

  /// @inheritdoc ITokensManager
  function isTokenUnderManagement(
    address token
  ) external view returns (bool) {
    return _deployedTokens.contains(token);
  }

  /// @inheritdoc ITokensManager
  function getTokensDeployedBy(
    address deployer
  ) external view returns (address[] memory) {
    return _deployerTokens[deployer];
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view override(AccessControlEnumerable, CCIPReceiver) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  function _registryToken(address token, bool viaCCIPAdmin) internal {
    _registryModuleOwnerCustom.registerAdminViaOwner(token);
    _tokenAdminRegistry.acceptAdminRole(token);
    emit TokenRegistered(token, viaCCIPAdmin);
  }

  function _setPoolForToken(
    address token
  ) internal {
    _tokenAdminRegistry.setPool(token, _concentratedPool);
  }

  function _setRemoteTokensManager(uint64 chainSelector, address remoteTokensManager) internal {
    _remoteTokensManagers[chainSelector] = remoteTokensManager;
    emit RemoteTokensManagerSet(chainSelector, remoteTokensManager);
  }

  function _setTokenAdminRegistry(
    address tokenAdminRegistry
  ) internal {
    _tokenAdminRegistry = TokenAdminRegistry(tokenAdminRegistry);
    emit TokenAdminRegistrySet(tokenAdminRegistry);
  }

  function _setLinkToken(
    address link
  ) internal {
    _link = link;
    emit LinkTokenSet(link);
  }

  function _setRegistryModuleOwnerCustom(
    address registryModuleOwnerCustom
  ) internal {
    _registryModuleOwnerCustom = RegistryModuleOwnerCustom(registryModuleOwnerCustom);
    emit RegistryModuleOwnerCustomSet(registryModuleOwnerCustom);
  }

  function _setConcentratedPool(
    address concentratedPool
  ) internal {
    _concentratedPool = concentratedPool;
    emit ConcentratedPoolSet(concentratedPool);
  }

  function _mintTokenForDeployer(BurnMintERC677 token, uint256 amount, address deployer) internal {
    token.grantMintRole(address(this));
    BurnMintERC677(token).mint(deployer, amount);
    token.revokeMintRole(address(this));
  }

  function _buildCCIPMessage(
    TokenInfo calldata tokenInfo,
    uint64 destinationChainSelector,
    bool payWithNative
  ) internal view returns (Client.EVM2AnyMessage memory message) {
    if (_callBackGasLimits[destinationChainSelector] == 0) {
      revert InvalidCallBackGasLimit(destinationChainSelector);
    }
    // Create a CCIP message to create the token on the destination chain
    message = Client.EVM2AnyMessage({
      receiver: abi.encode(_remoteTokensManagers[destinationChainSelector]), // ABI-encoded receiver address
      data: abi.encode(msg.sender, tokenInfo, _thisChainSelector), // ABI-encoded string
      tokenAmounts: new Client.EVMTokenAmount[](0), // No tokens to transfer
      extraArgs: Client._argsToBytes(
        // Additional arguments, setting gas limit
        Client.EVMExtraArgsV2({
          gasLimit: _callBackGasLimits[destinationChainSelector], // Gas limit for the callback on the destination chain
          allowOutOfOrderExecution: true // Allows the message to be executed out of order relative to other messages from the same sender
         })
      ),
      // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
      feeToken: payWithNative ? address(0) : _link
    });
  }

  function _sendSponsoredMessage(
    uint64 destinationChainSelector,
    Client.EVM2AnyMessage memory message,
    uint256 fees,
    bool payWithNative
  ) internal {
    if (payWithNative) {
      _sendMessageWithNativeFee(destinationChainSelector, message, fees);
    } else {
      _sendMessageWithLinkFee(destinationChainSelector, message, fees);
    }
  }

  function _sendUnsponsoredMessage(
    uint64 destinationChainSelector,
    Client.EVM2AnyMessage memory message,
    uint256 fees,
    bool payWithNative
  ) internal {
    if (payWithNative) {
      if (msg.value < fees) revert InsufficientNativeFee();
      _sendMessageWithNativeFee(destinationChainSelector, message, fees);
    } else {
      IERC20(_link).transferFrom(msg.sender, address(this), fees);
      _sendMessageWithLinkFee(destinationChainSelector, message, fees);
    }
  }

  function _sendMessageWithNativeFee(
    uint64 destinationChainSelector,
    Client.EVM2AnyMessage memory message,
    uint256 fees
  ) internal {
    IRouterClient(i_ccipRouter).ccipSend{ value: fees }(destinationChainSelector, message);
  }

  function _sendMessageWithLinkFee(
    uint64 destinationChainSelector,
    Client.EVM2AnyMessage memory message,
    uint256 fees
  ) internal {
    IERC20(_link).approve(i_ccipRouter, fees);
    IRouterClient(i_ccipRouter).ccipSend(destinationChainSelector, message);
  }

  function _ccipReceive(
    Client.Any2EVMMessage memory message
  ) internal override {
    (address deployer, TokenInfo memory tokenInfo, uint64 sourceChainSelector) =
      abi.decode(message.data, (address, TokenInfo, uint64));
    _onlyRemoteTokensManager(sourceChainSelector, abi.decode(message.sender, (address)));
    bytes32 salt = keccak256(
      abi.encodePacked(
        tokenInfo.name, tokenInfo.symbol, tokenInfo.decimals, tokenInfo.initialSupply, _deployerTokens[deployer].length
      )
    );
    BurnMintERC677 token =
      new BurnMintERC677{ salt: salt }(tokenInfo.name, tokenInfo.symbol, tokenInfo.decimals, tokenInfo.initialSupply);
    _deployerTokens[deployer].push(address(token));
    _tokenDeployers[address(token)] = deployer;
    _mintTokenForDeployer(token, tokenInfo.mintAmount, deployer);
    token.grantMintAndBurnRoles(_concentratedPool);
    _deployedTokens.add(address(token));
    _remoteTokens[address(token)][sourceChainSelector] = address(token);
    // Register the token
    _registryToken(address(token), true);
    _setPoolForToken(address(token));
    // Transfer ownership back to the deployer.
    token.transferOwnership(deployer);
    emit TokenCreated(_thisChainSelector, address(token), deployer, tokenInfo, message.messageId);
  }

  function _onlyRemoteTokensManager(uint64 chainSelector, address sender) internal view {
    if (sender != _remoteTokensManagers[chainSelector]) {
      revert UnauthorizedRemoteTokensManager(sender);
    }
  }
}
