// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.12;

import "solmate/utils/FixedPointMathLib.sol";

library Math {
  /// @notice Multiplies two wads (18 decimal numbers) and returns the result as a wad
  function wmul(uint256 x, uint256 y) internal returns (uint256) {
    return FixedPointMathLib.fmul(x, y, FixedPointMathLib.WAD);
  }
  
  /// @notice Divides two wads (18 decimal numbers) and returns the result as a wad
  function wdiv(uint256 x, uint256 y) internal returns (uint256) {
    return FixedPointMathLib.fdiv(x, y, FixedPointMathLib.WAD);
  }
}
