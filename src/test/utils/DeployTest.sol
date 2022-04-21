// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import "./DeployAll.sol";
import "./DSTestPlus.sol";
import "forge-std/console.sol";

/**
 * @dev Adds additional config after deployment to facilitate testing
 */
contract DeployTest is DeployAll, DSTestPlus {
  // Registry operations
  bytes4 public setEntityStatus = bytes4(keccak256("setEntityStatus(address,bool)"));

  // Entity operations
  bytes4 public entityTransfer = bytes4(keccak256("transfer(address,uint256)"));
  bytes4 public setOrgId = bytes4(keccak256("setOrgId(bytes32)"));
  bytes4 public setManager = bytes4(keccak256("setManager(address)"));

  function setUp() public virtual override {
    super.setUp();

    vm.label(board, "board");
    vm.label(user1, "user1");
    vm.label(treasury, "treasury");
    vm.label(capitalCommittee, "capital committee");

    vm.startPrank(board);
    globalTestRegistry.setFactoryApproval(address(orgFundFactory), true);
    
    // role 2: P_02	Transfer balances between entitys
    globalTestRegistry.setRoleCapability(2, entityPerms, entityTransfer, true); 
    globalTestRegistry.setUserRole(capitalCommittee, 2, true);

    // role 5: P_05	Enable/disable entities
    globalTestRegistry.setRoleCapability(5, address(globalTestRegistry), setEntityStatus, true);
    globalTestRegistry.setUserRole(capitalCommittee, 5, true);

    // role 6: P_06	Change an org's TaxID
    globalTestRegistry.setRoleCapability(6, entityPerms, setOrgId, true);
    globalTestRegistry.setUserRole(capitalCommittee, 6, true);
    
    // role 7: P_07	Change entity's manager address
    globalTestRegistry.setRoleCapability(7, entityPerms, setManager, true);
    globalTestRegistry.setUserRole(capitalCommittee, 7, true);

    vm.stopPrank();
  }
}
