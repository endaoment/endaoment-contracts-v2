// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import "./DeployAll.sol";
import "./DSTestPlus.sol";
import { ISwapWrapper } from "../../interfaces/ISwapWrapper.sol";
import { UniV3Wrapper } from "../../swapWrappers/UniV3Wrapper.sol";

/**
 * @dev Adds additional config after deployment to facilitate testing
 */
contract DeployTest is DeployAll, DSTestPlus {
  // Entity Types
  uint8 public constant OrgType = 1;
  uint8 public constant FundType = 2;

  // Registry operations
  bytes4 public setEntityStatus = bytes4(keccak256("setEntityStatus(address,bool)"));
  bytes4 public setDefaultDonationFee = bytes4(keccak256("setDefaultDonationFee(uint8,uint32)"));
  bytes4 public setDonationFeeReceiverOverride = bytes4(keccak256("setDonationFeeReceiverOverride(address,uint32)"));
  bytes4 public setDefaultTransferFee = bytes4(keccak256("setDefaultTransferFee(uint8,uint8,uint32)"));
  bytes4 public setTransferFeeSenderOverride = bytes4(keccak256("setTransferFeeSenderOverride(address,uint8,uint32)"));
  bytes4 public setTransferFeeReceiverOverride = bytes4(keccak256("setTransferFeeReceiverOverride(uint8,address,uint32)"));

  // Entity operations
  bytes4 public entityTransfer = bytes4(keccak256("transfer(address,uint256)"));
  bytes4 public setOrgId = bytes4(keccak256("setOrgId(bytes32)"));
  bytes4 public setManager = bytes4(keccak256("setManager(address)"));

  // Uni v3 swap wrapper
  address public uniV3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  ISwapWrapper uniV3SwapWrapper;

  function setUp() public virtual override {
    super.setUp();

    vm.label(board, "board");
    vm.label(user1, "user1");
    vm.label(user2, "user1");
    vm.label(treasury, "treasury");
    vm.label(capitalCommittee, "capital committee");
    vm.label(uniV3SwapRouter, "uniV3 swap router");

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

    // role 8: P_08 Change entity's fees
    globalTestRegistry.setRoleCapability(8, address(globalTestRegistry), setDefaultDonationFee, true);
    globalTestRegistry.setRoleCapability(8, address(globalTestRegistry), setDefaultTransferFee, true);
    globalTestRegistry.setUserRole(programCommittee, 8, true);

    // role 11: P_11 Change entity's outbound/inbound override fees
    globalTestRegistry.setRoleCapability(11, address(globalTestRegistry), setDonationFeeReceiverOverride, true);
    globalTestRegistry.setRoleCapability(11, address(globalTestRegistry), setTransferFeeSenderOverride, true);
    globalTestRegistry.setRoleCapability(11, address(globalTestRegistry), setTransferFeeReceiverOverride, true);
    globalTestRegistry.setUserRole(programCommittee, 11, true);

    vm.stopPrank();
  }
}
