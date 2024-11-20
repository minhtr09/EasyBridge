// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { IBurnMintERC20 } from "@chainlink/contracts-ccip/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";

import { Pool } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Pool.sol";
import { ConcentratedTokensPool } from "./ConcentratedTokensPool.sol";
import { console } from "forge-std/console.sol";

abstract contract BurnMintTokensPoolAbstract is ConcentratedTokensPool {
  /// @notice Contains the specific burn call for a pool.
  /// @dev overriding this method allows us to create pools with different burn signatures
  /// without duplicating the underlying logic.
  function _burn(uint256 amount, address token) internal virtual;

  /// @notice Burn the token in the pool
  /// @dev The _validateLockOrBurn check is an essential security check
  function lockOrBurn(
    Pool.LockOrBurnInV1 calldata lockOrBurnIn
  ) external virtual override returns (Pool.LockOrBurnOutV1 memory) {
    _validateLockOrBurn(lockOrBurnIn);

    _burn(lockOrBurnIn.amount, lockOrBurnIn.localToken);

    emit Burned(msg.sender, lockOrBurnIn.amount);
    bytes memory remoteToken = getRemoteToken(lockOrBurnIn.remoteChainSelector, lockOrBurnIn.localToken);

    return Pool.LockOrBurnOutV1({
      destTokenAddress: remoteToken.length == 0 ? abi.encode(lockOrBurnIn.localToken) : remoteToken,
      destPoolData: ""
    });
  }

  /// @notice Mint tokens from the pool to the recipient
  /// @dev The _validateReleaseOrMint check is an essential security check
  function releaseOrMint(
    Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
  ) external virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
    _validateReleaseOrMint(releaseOrMintIn);

    // Mint to the receiver
    IBurnMintERC20(releaseOrMintIn.localToken).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount);

    emit Minted(msg.sender, releaseOrMintIn.receiver, releaseOrMintIn.amount);

    return Pool.ReleaseOrMintOutV1({ destinationAmount: releaseOrMintIn.amount });
  }
}
