pragma solidity ^0.8.23;

interface ITokensManager {
  struct TokenInfo {
    string name;
    string symbol;
    uint8 decimals;
    uint256 initialSupply;
    uint256 mintAmount;
  }

  /// @dev Emitted when a token is removed from the tokens manager.
  event TokenRemoved(address indexed token);
  /// @dev Emitted when a token is registered in the tokens manager.
  event TokenRegistered(address indexed token, bool viaCCIPAdmin);
  /// @dev Emitted when a TokenAdminRegistry contract is set.
  event TokenAdminRegistrySet(address indexed tokenAdminRegistry);
  /// @dev Emitted when a RegistryModuleOwnerCustom contract is set.
  event RegistryModuleOwnerCustomSet(address indexed registryModuleOwnerCustom);
  /// @dev Emitted when a token is created on a chain.
  event TokenCreated(
    uint64 indexed chainSelector,
    address indexed token,
    address indexed deployer,
    TokenInfo tokenInfo,
    bytes32 messageId
  );
  /// @dev Emitted when a RemoteTokensManager contract is set for a chain.
  event RemoteTokensManagerSet(uint64 indexed chainSelector, address indexed remoteTokensManager);
  /// @dev Emitted when the callback gas limit is set for a chain.
  event CallBackGasLimitSet(uint64 indexed chainSelector, uint256 callBackGasLimit);
  /// @dev Emitted when the ConcentratedTokensPool contract address is set.
  event ConcentratedPoolSet(address indexed concentratedPool);
  /// @dev Emitted when the sponsored flag is set.
  event SponsoredSet(bool sponsored);
  /// @dev Emitted when the LINK token address is set.
  event LinkTokenSet(address indexed link);

  /// @dev Error emitted when a RemoteTokensManager contract is not authorized.
  error UnauthorizedRemoteTokensManager(address remoteTokensManager);
  /// @dev Error emitted when a msg.sender is not the token deployer.
  error UnauthorizedTokenDeployer(address token, address sender);
  /// @dev Error emitted when the callback gas limit is 0 for a chain.
  error InvalidCallBackGasLimit(uint64 chainSelector);
  /// @dev Error emitted when sender does not have enough native token to pay for the CCIP message.
  error InsufficientNativeFee();

  /**
   * @notice Creates a token under management.
   * @dev Deploy a ERC677 token and do all the necessary setup to be used with CCIP,
   * then create a CCIP message to deploy and set the token on the destination chain.
   * Emits a {TokenCreated} event.
   * Requirements:
   * - The destination chain must be supported.
   *
   * @param tokenInfo The information of the token to be created.
   * @param destinationChainSelector The chain selector of the destination chain.
   * @param payWithNative Whether to pay with native token or LINK.
   * @return The address of the created token.
   */
  function createTokenUnderManagement(
    TokenInfo memory tokenInfo,
    uint64 destinationChainSelector,
    bool payWithNative
  ) external payable returns (address);

  /**
   * @notice Sets the callback gas limit for a chain.
   * Emits a {CallBackGasLimitSet} event.
   * Requirements:
   * - The msg.sender must have the DEFAULT_ADMIN_ROLE.
   * @param chainSelector The chain selector.
   * @param gasLimit The gas limit.
   */
  function setCallBackGasLimit(uint64 chainSelector, uint256 gasLimit) external;

  /**
   * @notice Sets the RemoteTokensManager contract address for a chain.
   * Emits a {RemoteTokensManagerSet} event.
   * Requirements:
   * - The msg.sender must have the DEFAULT_ADMIN_ROLE.
   * - The chain selector must be supported.
   *
   * @param chainSelector The chain selector.
   * @param remoteTokensManager The address of the RemoteTokensManager contract.
   */
  function setRemoteTokensManager(uint64 chainSelector, address remoteTokensManager) external;

  /**
   * @notice Sets the ConcentratedTokensPool contract address.
   * Emits a {ConcentratedPoolSet} event.
   * Requirements:
   * - The msg.sender must have the DEFAULT_ADMIN_ROLE.
   *
   * @param concentratedPool The address of the ConcentratedTokensPool contract.
   */
  function setConcentratedPool(
    address concentratedPool
  ) external;

  /**
   * @notice Sets the sponsored flag.
   * Emits a {SponsoredSet} event.
   * Requirements:
   * - The msg.sender must have the DEFAULT_ADMIN_ROLE.
   * @param sponsored The sponsored flag.
   */
  function setSponsored(
    bool sponsored
  ) external;

  /**
   * @notice Removes a token from the tokens manager.
   * Emits a {TokenRemoved} event.
   * Requirements:
   * - The msg.sender must have the DEFAULT_ADMIN_ROLE or the deployer of the token.
   *
   * @param token The address of the token to be removed.
   */
  function removeToken(
    address token
  ) external;

  /**
   * @notice Returns all the managed tokens.
   * @return An array of addresses representing the managed tokens.
   */
  function getManagedTokens() external view returns (address[] memory);

  /**
   * @notice Checks if a token is under management.
   * @param token The address of the token to check.
   * @return True if the token is under management, false otherwise.
   */
  function isTokenUnderManagement(
    address token
  ) external view returns (bool);

  /**
   * @notice Returns all the tokens deployed by a deployer.
   * @param deployer The address of the deployer.
   * @return An array of addresses representing the tokens deployed by the deployer.
   */
  function getTokensDeployedBy(
    address deployer
  ) external view returns (address[] memory);
}
