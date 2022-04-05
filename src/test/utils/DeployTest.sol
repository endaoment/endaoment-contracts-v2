// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import "./DeployAll.sol";
import "./DSTestPlus.sol";

/**
 * @dev Adds additional config after deployment to facilitate testing
 */
contract DeployTest is DeployAll, DSTestPlus {
  function setUp() public virtual override {
    super.setUp();

    vm.label(admin, "admin");
    vm.label(user1, "user1");
    vm.label(treasury, "treasury");
  }
}
