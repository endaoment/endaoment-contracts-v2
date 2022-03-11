// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.12;

import "solmate/utils/FixedPointMathLib.sol";

import "./utils/DSTestPlus.sol";
import "../lib/Math.sol";

contract MathTest is DSTestPlus {
  using Math for uint256;

  uint256 internal constant WAD = 1e18;

  function testWmul(uint256 x, uint256 y) public {
    unchecked {
      // if x * y overflows, we shrink the values
      while (x != 0 && (x * y) / x != y) {
        x /= 2;
        y /= 2;
      }
    }
    assertEq(x.wmul(y), FixedPointMathLib.fmul(x, y, WAD));
  }

  function testWdiv(uint256 x, uint256 y) public {
    if (y == 0) y = 1; // prevent divide by zeros
    unchecked {
      // if x * WAD overflows, we shrink x
      while (x != 0 && (x * WAD) / x != WAD) {
        x /= 2;
      }
    }
    assertEq(x.wdiv(y), FixedPointMathLib.fdiv(x, y, WAD));
  }
}
