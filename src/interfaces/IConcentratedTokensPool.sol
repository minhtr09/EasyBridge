// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { RateLimiter } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";
import { IPoolV1 } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IPool.sol";

interface IConcentratedTokensPool is IPoolV1 {
  struct ChainUpdate {
    uint64 remoteChainSelector; // ──╮ Remote chain selector
    bool allowed; // ────────────────╯ Whether the chain should be enabled
    bytes remotePoolAddress; //     Address of the remote pool, ABI encoded in the case of a remote EVM chain.
    bytes[] remoteTokenAddresses; // Address of the remote tokens, ABI encoded in the case of a remote EVM chain.
    address[] tokens; // Address of the tokens will be mapped to the remote token addresses.
    RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
    RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
  }

  struct RemoteChainConfig {
    RateLimiter.TokenBucket outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
    RateLimiter.TokenBucket inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
    bytes remotePoolAddress; // Address of the remote pool, ABI encoded in the case of a remote EVM chain.
    mapping(address token => bytes remoteTokenAddress) remoteTokenAddresses; // Address of the remote token, ABI encoded in the case of a remote EVM chain.
  }

  error CallerIsNotARampOnRouter(address caller);
  error ZeroAddressNotAllowed();
  error SenderNotAllowed(address sender);
  error AllowListNotEnabled();
  error NonExistentChain(uint64 remoteChainSelector);
  error ChainNotAllowed(uint64 remoteChainSelector);
  error CursedByRMN();
  error ChainAlreadyExists(uint64 chainSelector);
  error InvalidSourcePoolAddress(bytes sourcePoolAddress);
  error InvalidToken(address token);
  error Unauthorized(address caller);
  error ArrayLengthMismatch();

  event Locked(address indexed sender, uint256 amount);
  event Burned(address indexed sender, uint256 amount);
  event Released(address indexed sender, address indexed recipient, uint256 amount);
  event Minted(address indexed sender, address indexed recipient, uint256 amount);
  event ChainAdded(
    uint64 remoteChainSelector,
    bytes[] remoteTokenAddresses,
    address[] tokens,
    RateLimiter.Config outboundRateLimiterConfig,
    RateLimiter.Config inboundRateLimiterConfig
  );
  event ChainConfigured(
    uint64 remoteChainSelector,
    RateLimiter.Config outboundRateLimiterConfig,
    RateLimiter.Config inboundRateLimiterConfig
  );
  event ChainRemoved(uint64 remoteChainSelector);
  event RemotePoolSet(uint64 indexed remoteChainSelector, bytes previousPoolAddress, bytes remotePoolAddress);
  event AllowListAdd(address sender);
  event AllowListRemove(address sender);
  event RouterUpdated(address oldRouter, address newRouter);
  event TokenAdded(address token);
  event TokenRemoved(address token);
}
