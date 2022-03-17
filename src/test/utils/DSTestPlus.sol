// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.12;

import { DSTestPlus as DSTestPlusSolmate } from "solmate/test/utils/DSTestPlus.sol";
import "forge-std/stdlib.sol";
import {Vm} from "forge-std/Vm.sol";

// Extends DSPlus with additional helper methods
contract DSTestPlus is DSTestPlusSolmate {
  // Cheatcodes live at a specific address; you can think of them as precompiles in a sense
  Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

  // Takes a human-readable value and scales it (named after the ethers.js method with the same functionality)
  function parseUnits(uint256 x, uint256 decimals) internal pure returns (uint256) {
    return x * 10 ** decimals;
  }
}
