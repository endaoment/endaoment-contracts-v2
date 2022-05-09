// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import "./DeployAll.sol";
import "./DSTestPlus.sol";
import { ISwapWrapper } from "../../interfaces/ISwapWrapper.sol";
import { UniV3Wrapper } from "../../swapWrappers/UniV3Wrapper.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

/**
 * @dev Adds additional config after deployment to facilitate testing
 */
contract DeployTest is DeployAll, DSTestPlus {
  using stdStorage for StdStorage;

  // Entity Types
  uint8 public constant OrgType = 1;
  uint8 public constant FundType = 2;

  uint256 public constant MIN_DONATION_TRANSFER_AMOUNT = 5; // 0.0005 cents USDC
  uint256 public constant MAX_DONATION_TRANSFER_AMOUNT = 1_000_000_000_000_000; // $1 Billion USDC

  // Entity special targets for auth permissions
  address orgTarget = address(bytes20(bytes.concat("entity", bytes1(uint8(1)))));
  address fundTarget = address(bytes20(bytes.concat("entity", bytes1(uint8(2)))));

  // Registry operations
  bytes4 public setEntityStatus = bytes4(keccak256("setEntityStatus(address,bool)"));
  bytes4 public setDefaultDonationFee = bytes4(keccak256("setDefaultDonationFee(uint8,uint32)"));
  bytes4 public setDonationFeeReceiverOverride = bytes4(keccak256("setDonationFeeReceiverOverride(address,uint32)"));
  bytes4 public setDefaultTransferFee = bytes4(keccak256("setDefaultTransferFee(uint8,uint8,uint32)"));
  bytes4 public setTransferFeeSenderOverride = bytes4(keccak256("setTransferFeeSenderOverride(address,uint8,uint32)"));
  bytes4 public setTransferFeeReceiverOverride = bytes4(keccak256("setTransferFeeReceiverOverride(uint8,address,uint32)"));
  bytes4 public setTreasury = bytes4(keccak256("setTreasury(address)"));

  // Entity operations
  bytes4 public entityTransfer = bytes4(keccak256("transfer(address,uint256)"));
  bytes4 public setOrgId = bytes4(keccak256("setOrgId(bytes32)"));
  bytes4 public setManager = bytes4(keccak256("setManager(address)"));

  // NDAO operations
  bytes4 public ndaoMint = bytes4(keccak256("mint(address,uint256)"));

  // NVT operations
  bytes4 public nvtVestLock = bytes4(keccak256("vestLock(address,uint256,uint256)"));
  bytes4 public nvtClawback = bytes4(keccak256("clawback(address)"));

  // Rolling Merkle Distributor operations
  bytes4 public rollover = bytes4(keccak256("rollover(bytes32,uint256)"));

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
    vm.label(tokenTrust, "token trust");
    vm.label(uniV3SwapRouter, "uniV3 swap router");
    vm.label(address(ndao), "NDAO");
    vm.label(address(nvt), "NVT");
    vm.label(address(distributor), "distributor");
    vm.label(address(baseDistributor), "base distributor");

    vm.startPrank(board);

    globalTestRegistry.setFactoryApproval(address(orgFundFactory), true);

    // TODO: Give board & capital committee mint capability (Use functional requirements doc)

    // role 2: P_02	Transfer balances between entities
    globalTestRegistry.setRoleCapability(2, orgTarget, entityTransfer, true);
    globalTestRegistry.setRoleCapability(2, fundTarget, entityTransfer, true);
    globalTestRegistry.setUserRole(capitalCommittee, 2, true);

    // role 5: P_05	Enable/disable entities
    globalTestRegistry.setRoleCapability(5, address(globalTestRegistry), setEntityStatus, true);
    globalTestRegistry.setUserRole(capitalCommittee, 5, true);

    // role 6: P_06	Change an org's TaxID
    globalTestRegistry.setRoleCapability(6, orgTarget, setOrgId, true);
    globalTestRegistry.setUserRole(capitalCommittee, 6, true);

    // role 7: P_07	Change entity's manager address
    globalTestRegistry.setRoleCapability(7, orgTarget, setManager, true);
    globalTestRegistry.setRoleCapability(7, fundTarget, setManager, true);
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

    // role 17: P_17 NDAO Rolling Merkle Distributor Rollover
    globalTestRegistry.setRoleCapability(17, address(distributor), rollover, true);
    globalTestRegistry.setUserRole(tokenTrust, 17, true);

    // role 18: P_18 Base Token Rolling Merkle Distributor Rollover
    globalTestRegistry.setRoleCapability(18, address(baseDistributor), rollover, true);
    globalTestRegistry.setUserRole(tokenTrust, 18, true);

    // role 22: P_22 Mint NDAO
    globalTestRegistry.setRoleCapability(22, address(ndao), ndaoMint, true);
    globalTestRegistry.setUserRole(capitalCommittee, 22, true);

    // role 23: P_23 NVT Vesting & Clawback
    globalTestRegistry.setRoleCapability(23, address(nvt), nvtVestLock, true);
    globalTestRegistry.setRoleCapability(23, address(nvt), nvtClawback, true);
    globalTestRegistry.setUserRole(capitalCommittee, 23, true);

    vm.stopPrank();
  }

  // local helper function to set an entity's balance
  function _setEntityBalance(Entity _entity, uint256 _newBalance) internal {
      stdstore
          .target(address(_entity))
          .sig(_entity.balance.selector)
          .checked_write(_newBalance);
      ERC20 _baseToken = globalTestRegistry.baseToken();
      deal(address(_baseToken), address(_entity), _newBalance);
  }
}
