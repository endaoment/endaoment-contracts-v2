// SPDX-License-Identifier: BSD 3-Claused
pragma solidity 0.8.13;

import { DSTestPlus as DSTestPlusSolmate } from "solmate/test/utils/DSTestPlus.sol";
import "forge-std/Test.sol";
import { Registry } from "../../Registry.sol";
import { Entity } from "../../Entity.sol";

// Extends DSPlus with additional helper methods
contract DSTestPlus is Test {

  // Takes a human-readable value and scales it (named after the ethers.js method with the same functionality)
  function parseUnits(uint256 x, uint256 decimals) internal pure returns (uint256) {
    return x * 10 ** decimals;
  }

  function assertEq(Registry a, Registry b) internal {
    if (address(a) != address(b)) {
      emit log("Error: a == b not satisfied [address]");
      emit log_named_address("  Expected", address(b));
      emit log_named_address("    Actual", address(a));
      fail();
    }
  }
}
