// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import { ITypeAndVersion } from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import { IBurnMintERC20 } from "@chainlink/contracts-ccip/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import { BurnMintTokensPoolAbstract } from "./BurnMintTokensPoolAbstract.sol";
import { ConcentratedTokensPool } from "./ConcentratedTokensPool.sol";
/// @notice This pool mints and burns a 3rd-party token.
/// @dev Pool whitelisting mode is set in the constructor and cannot be modified later.
/// It either accepts any address as originalSender, or only accepts whitelisted originalSender.
/// The only way to change whitelisting mode is to deploy a new pool.
/// If that is expected, please make sure the token's burner/minter roles are adjustable.
/// @dev This contract is a variant of BurnMintTokenPool that uses `burn(amount)`.

contract BurnMintTokensPool is BurnMintTokensPoolAbstract, ITypeAndVersion {
  string public constant override typeAndVersion = "BurnMintTokenPool 1.5.0";

  constructor(
    address[] memory tokens,
    address[] memory allowlist,
    address rmnProxy,
    address router
  ) ConcentratedTokensPool(tokens, allowlist, rmnProxy, router) { }

  /// @inheritdoc BurnMintTokensPoolAbstract
  function _burn(uint256 amount, address token) internal virtual override {
    IBurnMintERC20(token).burn(amount);
  }
}
