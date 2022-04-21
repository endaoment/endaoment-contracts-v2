// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { DSTestPlus as DSTestPlusSolmate } from "solmate/test/utils/DSTestPlus.sol";
import "forge-std/stdlib.sol";
import {Vm} from "forge-std/Vm.sol";

import { Registry } from "../../Registry.sol";

// Extends DSPlus with additional helper methods
contract DSTestPlus is DSTestPlusSolmate, stdCheats {
  // Cheatcodes live at a specific address; you can think of them as precompiles in a sense
  Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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

  function assertEq(bool a, bool b) internal {
    if (a != b) {
      emit log("Error: a == b not satisfied [bool]");
      emit log_named_uint("  Expected", b ? uint256(1) : uint256(0));
      emit log_named_uint("    Actual", a ? uint256(1) : uint256(0));
      fail();
    }
  }

}
