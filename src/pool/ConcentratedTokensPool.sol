// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { IPoolV1 } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IPool.sol";
import { IRMN } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRMN.sol";
import { IRouter } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouter.sol";

import { OwnerIsCreator } from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import { Pool } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Pool.sol";
import { RateLimiter } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";

import { IERC20 } from
  "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from
  "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v5.0.2/contracts/utils/introspection/IERC165.sol";
import { EnumerableSet } from
  "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v5.0.2/contracts/utils/structs/EnumerableSet.sol";
import { ITokensManager } from "../interfaces/ITokensManager.sol";
import { IConcentratedTokensPool } from "../interfaces/IConcentratedTokensPool.sol";
/// @notice This contract is a variant of Chainlink's TokenPool contract that allows for a tokens manager to be set.
/// All tokens are managed by the TokensManager contract are considered under management or can be added manually to the pool.

abstract contract ConcentratedTokensPool is IConcentratedTokensPool, OwnerIsCreator {
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;
  using RateLimiter for RateLimiter.TokenBucket;

  /// @dev The address of the RMN proxy
  address internal immutable i_rmnProxy;
  /// @dev The immutable flag that indicates if the pool is access-controlled.
  bool internal immutable i_allowlistEnabled;
  /// @dev A set of addresses allowed to trigger lockOrBurn as original senders.
  /// Only takes effect if i_allowlistEnabled is true.
  /// This can be used to ensure only token-issuer specified addresses can
  /// move tokens.
  EnumerableSet.AddressSet internal s_allowList;
  /// @dev A set of tokens that are managed by this pool.
  EnumerableSet.AddressSet internal s_tokens;
  /// @dev The address of the router
  IRouter internal s_router;
  /// @dev A set of allowed chain selectors. We want the allowlist to be enumerable to
  /// be able to quickly determine (without parsing logs) who can access the pool.
  /// @dev The chain selectors are in uint256 format because of the EnumerableSet implementation.
  EnumerableSet.UintSet internal s_remoteChainSelectors;
  mapping(uint64 remoteChainSelector => RemoteChainConfig) internal s_remoteChainConfigs;
  /// @notice The address of the rate limiter admin.
  /// @dev Can be address(0) if none is configured.
  address internal s_rateLimitAdmin;
  /// @dev The address of the tokens manager
  ITokensManager internal s_tokenManager;

  constructor(address[] memory tokens, address[] memory allowlist, address rmnProxy, address router) {
    if (rmnProxy == address(0) || router == address(0)) {
      revert ZeroAddressNotAllowed();
    }
    i_rmnProxy = rmnProxy;
    s_router = IRouter(router);

    _updateTokens(tokens, new address[](0));

    // Pool can be set as permissioned or permissionless at deployment time only to save hot-path gas.
    i_allowlistEnabled = allowlist.length > 0;
    if (i_allowlistEnabled) {
      _applyAllowListUpdates(new address[](0), allowlist);
    }
  }

  /// @notice Get RMN proxy address
  /// @return rmnProxy Address of RMN proxy
  function getRmnProxy() public view returns (address rmnProxy) {
    return i_rmnProxy;
  }

  /// @inheritdoc IPoolV1
  function isSupportedToken(
    address token
  ) public view virtual returns (bool) {
    if (address(s_tokenManager) != address(0)) {
      return s_tokenManager.isTokenUnderManagement(token);
    }
    return s_tokens.contains(token);
  }

  /// @notice Gets the IERC20 tokens that this pool can lock or burn which includes both managed tokens by the tokens manager and the tokens added manually to the pool.
  /// @return tokens The IERC20 token representations.
  function getTokens() public view returns (address[] memory tokens) {
    address[] memory managedTokens = s_tokenManager.getManagedTokens();
    tokens = new address[](s_tokens.length() + managedTokens.length);
    for (uint256 i; i < s_tokens.length(); ++i) {
      tokens[i] = s_tokens.at(i);
    }
    for (uint256 i; i < managedTokens.length; ++i) {
      tokens[s_tokens.length() + i] = managedTokens[i];
    }
    return tokens;
  }

  /// @notice Gets the pool's Router
  /// @return router The pool's Router
  function getRouter() public view returns (address router) {
    return address(s_router);
  }

  /// @notice Sets the pool's Router
  /// @param newRouter The new Router
  function setRouter(
    address newRouter
  ) public onlyOwner {
    if (newRouter == address(0)) revert ZeroAddressNotAllowed();
    address oldRouter = address(s_router);
    s_router = IRouter(newRouter);

    emit RouterUpdated(oldRouter, newRouter);
  }

  function setTokensManager(
    address tokensManager
  ) external onlyOwner {
    s_tokenManager = ITokensManager(tokensManager);
  }

  /// @notice Signals which version of the pool interface is supported
  function supportsInterface(
    bytes4 interfaceId
  ) public pure virtual override returns (bool) {
    return interfaceId == Pool.CCIP_POOL_V1 || interfaceId == type(IPoolV1).interfaceId
      || interfaceId == type(IERC165).interfaceId;
  }

  // ================================================================
  // │                         Validation                           │
  // ================================================================

  /// @notice Validates the lock or burn input for correctness on
  /// - token to be locked or burned
  /// - RMN curse status
  /// - allowlist status
  /// - if the sender is a valid onRamp
  /// - rate limit status
  /// @param lockOrBurnIn The input to validate.
  /// @dev This function should always be called before executing a lock or burn. Not doing so would allow
  /// for various exploits.
  function _validateLockOrBurn(
    Pool.LockOrBurnInV1 memory lockOrBurnIn
  ) internal {
    if (!isSupportedToken(lockOrBurnIn.localToken)) {
      revert InvalidToken(lockOrBurnIn.localToken);
    }
    if (IRMN(i_rmnProxy).isCursed(bytes16(uint128(lockOrBurnIn.remoteChainSelector)))) revert CursedByRMN();
    _checkAllowList(lockOrBurnIn.originalSender);

    _onlyOnRamp(lockOrBurnIn.remoteChainSelector);
    _consumeOutboundRateLimit(lockOrBurnIn.remoteChainSelector, lockOrBurnIn.amount, lockOrBurnIn.localToken);
  }

  /// @notice Validates the release or mint input for correctness on
  /// - token to be released or minted
  /// - RMN curse status
  /// - if the sender is a valid offRamp
  /// - if the source pool is valid
  /// - rate limit status
  /// @param releaseOrMintIn The input to validate.
  /// @dev This function should always be called before executing a release or mint. Not doing so would allow
  /// for various exploits.
  function _validateReleaseOrMint(
    Pool.ReleaseOrMintInV1 memory releaseOrMintIn
  ) internal {
    if (!isSupportedToken(releaseOrMintIn.localToken)) {
      revert InvalidToken(releaseOrMintIn.localToken);
    }
    if (IRMN(i_rmnProxy).isCursed(bytes16(uint128(releaseOrMintIn.remoteChainSelector)))) revert CursedByRMN();
    _onlyOffRamp(releaseOrMintIn.remoteChainSelector);

    // Validates that the source pool address is configured on this pool.
    bytes memory configuredRemotePool = getRemotePool(releaseOrMintIn.remoteChainSelector);
    if (
      configuredRemotePool.length == 0
        || keccak256(releaseOrMintIn.sourcePoolAddress) != keccak256(configuredRemotePool)
    ) {
      revert InvalidSourcePoolAddress(releaseOrMintIn.sourcePoolAddress);
    }
    _consumeInboundRateLimit(releaseOrMintIn.remoteChainSelector, releaseOrMintIn.amount, releaseOrMintIn.localToken);
  }

  // ================================================================
  // │                     Chain permissions                        │
  // ================================================================

  /// @notice Gets the pool address on the remote chain, in case of remote token has the same address as the local token.
  /// @param remoteChainSelector Remote chain selector.
  /// @dev To support non-evm chains, this value is encoded into bytes
  function getRemotePool(
    uint64 remoteChainSelector
  ) public view returns (bytes memory) {
    return s_remoteChainConfigs[remoteChainSelector].remotePoolAddress;
  }

  /// @notice Gets the token address on the remote chain.
  /// @param remoteChainSelector Remote chain selector.
  /// @dev To support non-evm chains, this value is encoded into bytes
  function getRemoteToken(uint64 remoteChainSelector, address token) public view returns (bytes memory) {
    return s_remoteChainConfigs[remoteChainSelector].remoteTokenAddresses[token];
  }

  /// @notice Sets the remote pool address for a given chain selector.
  /// @param remoteChainSelector The remote chain selector for which the remote pool address is being set.
  /// @param remotePoolAddress The address of the remote pool.
  function setRemotePool(uint64 remoteChainSelector, bytes calldata remotePoolAddress) external onlyOwner {
    if (!isSupportedChain(remoteChainSelector)) {
      revert NonExistentChain(remoteChainSelector);
    }

    bytes memory prevAddress = s_remoteChainConfigs[remoteChainSelector].remotePoolAddress;
    s_remoteChainConfigs[remoteChainSelector].remotePoolAddress = remotePoolAddress;

    emit RemotePoolSet(remoteChainSelector, prevAddress, remotePoolAddress);
  }

  /// @inheritdoc IPoolV1
  function isSupportedChain(
    uint64 remoteChainSelector
  ) public view returns (bool) {
    return s_remoteChainSelectors.contains(remoteChainSelector);
  }

  /// @notice Get list of allowed chains
  /// @return list of chains.
  function getSupportedChains() public view returns (uint64[] memory) {
    uint256[] memory uint256ChainSelectors = s_remoteChainSelectors.values();
    uint64[] memory chainSelectors = new uint64[](uint256ChainSelectors.length);
    for (uint256 i = 0; i < uint256ChainSelectors.length; ++i) {
      chainSelectors[i] = uint64(uint256ChainSelectors[i]);
    }

    return chainSelectors;
  }

  /// @notice Sets the permissions for a list of chains selectors. Actual senders for these chains
  /// need to be allowed on the Router to interact with this pool.
  /// @dev Only callable by the owner
  /// @param chains A list of chains and their new permission status & rate limits. Rate limits
  /// are only used when the chain is being added through `allowed` being true.
  function applyChainUpdates(
    ChainUpdate[] calldata chains
  ) external virtual onlyOwner {
    for (uint256 i = 0; i < chains.length; ++i) {
      ChainUpdate memory update = chains[i];
      RateLimiter._validateTokenBucketConfig(update.outboundRateLimiterConfig, !update.allowed);
      RateLimiter._validateTokenBucketConfig(update.inboundRateLimiterConfig, !update.allowed);

      if (update.allowed) {
        // If the chain already exists, revert
        if (!s_remoteChainSelectors.add(update.remoteChainSelector)) {
          revert ChainAlreadyExists(update.remoteChainSelector);
        }

        if (update.remotePoolAddress.length == 0) {
          revert ZeroAddressNotAllowed();
        }

        _updateRemoteChainConfig(update);

        emit ChainAdded(
          update.remoteChainSelector,
          update.remoteTokenAddresses,
          update.tokens,
          update.outboundRateLimiterConfig,
          update.inboundRateLimiterConfig
        );
      } else {
        // If the chain doesn't exist, revert
        if (!s_remoteChainSelectors.remove(update.remoteChainSelector)) {
          revert NonExistentChain(update.remoteChainSelector);
        }

        delete s_remoteChainConfigs[update.remoteChainSelector];

        emit ChainRemoved(update.remoteChainSelector);
      }
    }
  }

  // ================================================================
  // │                        Rate limiting                         │
  // ================================================================

  /// @notice Sets the rate limiter admin address.
  /// @dev Only callable by the owner.
  /// @param rateLimitAdmin The new rate limiter admin address.
  function setRateLimitAdmin(
    address rateLimitAdmin
  ) external onlyOwner {
    s_rateLimitAdmin = rateLimitAdmin;
  }

  /// @notice Gets the rate limiter admin address.
  function getRateLimitAdmin() external view returns (address) {
    return s_rateLimitAdmin;
  }

  /// @notice Consumes outbound rate limiting capacity in this pool
  function _consumeOutboundRateLimit(uint64 remoteChainSelector, uint256 amount, address token) internal {
    s_remoteChainConfigs[remoteChainSelector].outboundRateLimiterConfig._consume(amount, token);
  }

  /// @notice Consumes inbound rate limiting capacity in this pool
  function _consumeInboundRateLimit(uint64 remoteChainSelector, uint256 amount, address token) internal {
    s_remoteChainConfigs[remoteChainSelector].inboundRateLimiterConfig._consume(amount, token);
  }

  /// @notice Gets the token bucket with its values for the block it was requested at.
  /// @return The token bucket.
  function getCurrentOutboundRateLimiterState(
    uint64 remoteChainSelector
  ) external view returns (RateLimiter.TokenBucket memory) {
    return s_remoteChainConfigs[remoteChainSelector].outboundRateLimiterConfig._currentTokenBucketState();
  }

  /// @notice Gets the token bucket with its values for the block it was requested at.
  /// @return The token bucket.
  function getCurrentInboundRateLimiterState(
    uint64 remoteChainSelector
  ) external view returns (RateLimiter.TokenBucket memory) {
    return s_remoteChainConfigs[remoteChainSelector].inboundRateLimiterConfig._currentTokenBucketState();
  }

  /// @notice Sets the chain rate limiter config.
  /// @param remoteChainSelector The remote chain selector for which the rate limits apply.
  /// @param outboundConfig The new outbound rate limiter config, meaning the onRamp rate limits for the given chain.
  /// @param inboundConfig The new inbound rate limiter config, meaning the offRamp rate limits for the given chain.
  function setChainRateLimiterConfig(
    uint64 remoteChainSelector,
    RateLimiter.Config memory outboundConfig,
    RateLimiter.Config memory inboundConfig
  ) external {
    if (msg.sender != s_rateLimitAdmin && msg.sender != owner()) {
      revert Unauthorized(msg.sender);
    }

    _setRateLimitConfig(remoteChainSelector, outboundConfig, inboundConfig);
  }

  function _setRateLimitConfig(
    uint64 remoteChainSelector,
    RateLimiter.Config memory outboundConfig,
    RateLimiter.Config memory inboundConfig
  ) internal {
    if (!isSupportedChain(remoteChainSelector)) {
      revert NonExistentChain(remoteChainSelector);
    }
    RateLimiter._validateTokenBucketConfig(outboundConfig, false);
    s_remoteChainConfigs[remoteChainSelector].outboundRateLimiterConfig._setTokenBucketConfig(outboundConfig);
    RateLimiter._validateTokenBucketConfig(inboundConfig, false);
    s_remoteChainConfigs[remoteChainSelector].inboundRateLimiterConfig._setTokenBucketConfig(inboundConfig);
    emit ChainConfigured(remoteChainSelector, outboundConfig, inboundConfig);
  }

  // ================================================================
  // │                           Access                             │
  // ================================================================

  /// @notice Checks whether remote chain selector is configured on this contract, and if the msg.sender
  /// is a permissioned onRamp for the given chain on the Router.
  function _onlyOnRamp(
    uint64 remoteChainSelector
  ) internal view {
    if (!isSupportedChain(remoteChainSelector)) {
      revert ChainNotAllowed(remoteChainSelector);
    }
    if (!(msg.sender == s_router.getOnRamp(remoteChainSelector))) {
      revert CallerIsNotARampOnRouter(msg.sender);
    }
  }

  /// @notice Checks whether remote chain selector is configured on this contract, and if the msg.sender
  /// is a permissioned offRamp for the given chain on the Router.
  function _onlyOffRamp(
    uint64 remoteChainSelector
  ) internal view {
    if (!isSupportedChain(remoteChainSelector)) {
      revert ChainNotAllowed(remoteChainSelector);
    }
    if (!s_router.isOffRamp(remoteChainSelector, msg.sender)) {
      revert CallerIsNotARampOnRouter(msg.sender);
    }
  }

  // ================================================================
  // │                          Allowlist                           │
  // ================================================================

  function _checkAllowList(
    address sender
  ) internal view {
    if (i_allowlistEnabled) {
      if (!s_allowList.contains(sender)) {
        revert SenderNotAllowed(sender);
      }
    }
  }

  /// @notice Gets whether the allowList functionality is enabled.
  /// @return true is enabled, false if not.
  function getAllowListEnabled() external view returns (bool) {
    return i_allowlistEnabled;
  }

  /// @notice Gets the allowed addresses.
  /// @return The allowed addresses.
  function getAllowList() external view returns (address[] memory) {
    return s_allowList.values();
  }

  /// @notice Apply updates to the allow list.
  /// @param removes The addresses to be removed.
  /// @param adds The addresses to be added.
  function applyAllowListUpdates(address[] calldata removes, address[] calldata adds) external onlyOwner {
    _applyAllowListUpdates(removes, adds);
  }

  /// @notice Internal version of applyAllowListUpdates to allow for reuse in the constructor.
  function _applyAllowListUpdates(address[] memory removes, address[] memory adds) internal {
    if (!i_allowlistEnabled) revert AllowListNotEnabled();

    for (uint256 i = 0; i < removes.length; ++i) {
      address toRemove = removes[i];
      if (s_allowList.remove(toRemove)) {
        emit AllowListRemove(toRemove);
      }
    }
    for (uint256 i = 0; i < adds.length; ++i) {
      address toAdd = adds[i];
      if (toAdd == address(0)) {
        continue;
      }
      if (s_allowList.add(toAdd)) {
        emit AllowListAdd(toAdd);
      }
    }
  }

  function updateTokens(address[] memory adds, address[] memory removes) external onlyOwner {
    _updateTokens(adds, removes);
  }

  function _updateTokens(address[] memory adds, address[] memory removes) internal {
    for (uint256 i = 0; i < adds.length; ++i) {
      address toAdd = adds[i];
      if (toAdd == address(0)) {
        continue;
      }
      s_tokens.add(toAdd);
      emit TokenAdded(toAdd);
    }
    for (uint256 i = 0; i < removes.length; ++i) {
      address toRemove = removes[i];
      if (toRemove == address(0)) {
        continue;
      }
      s_tokens.remove(toRemove);
      emit TokenRemoved(toRemove);
    }
  }

  function _updateRemoteChainConfig(
    ChainUpdate memory update
  ) internal {
    if (update.remoteTokenAddresses.length != update.tokens.length) {
      revert ArrayLengthMismatch();
    }
    for (uint256 i = 0; i < update.tokens.length; ++i) {
      if (!isSupportedToken(update.tokens[i])) {
        revert InvalidToken(update.tokens[i]);
      }
      s_remoteChainConfigs[update.remoteChainSelector].remoteTokenAddresses[update.tokens[i]] =
        update.remoteTokenAddresses[i];
    }

    s_remoteChainConfigs[update.remoteChainSelector].outboundRateLimiterConfig = RateLimiter.TokenBucket({
      rate: update.outboundRateLimiterConfig.rate,
      capacity: update.outboundRateLimiterConfig.capacity,
      tokens: update.outboundRateLimiterConfig.capacity,
      lastUpdated: uint32(block.timestamp),
      isEnabled: update.outboundRateLimiterConfig.isEnabled
    });
    s_remoteChainConfigs[update.remoteChainSelector].inboundRateLimiterConfig = RateLimiter.TokenBucket({
      rate: update.inboundRateLimiterConfig.rate,
      capacity: update.inboundRateLimiterConfig.capacity,
      tokens: update.inboundRateLimiterConfig.capacity,
      lastUpdated: uint32(block.timestamp),
      isEnabled: update.inboundRateLimiterConfig.isEnabled
    });
    s_remoteChainConfigs[update.remoteChainSelector].remotePoolAddress = update.remotePoolAddress;
  }
}
