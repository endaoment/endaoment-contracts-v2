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

  uint256 public constant MIN_ENTITY_TRANSACTION_AMOUNT = 5; // 0.0005 cents USDC
  uint256 public constant MAX_ENTITY_TRANSACTION_AMOUNT = 1_000_000_000_000_000; // $1 Billion USDC

  // special targets for auth permissions
  address orgTarget = address(bytes20(bytes.concat("entity", bytes1(uint8(1)))));
  address fundTarget = address(bytes20(bytes.concat("entity", bytes1(uint8(2)))));
  address portfolioTarget = address(bytes20("portfolio"));

  // Registry operations
  bytes4 public setEntityStatus = bytes4(keccak256("setEntityStatus(address,bool)"));
  bytes4 public setDefaultDonationFee = bytes4(keccak256("setDefaultDonationFee(uint8,uint32)"));
  bytes4 public setDonationFeeReceiverOverride = bytes4(keccak256("setDonationFeeReceiverOverride(address,uint32)"));
  bytes4 public setDefaultPayoutFee = bytes4(keccak256("setDefaultPayoutFee(uint8,uint32)"));
  bytes4 public setPayoutFeeOverride = bytes4(keccak256("setPayoutFeeOverride(address,uint32)"));
  bytes4 public setDefaultTransferFee = bytes4(keccak256("setDefaultTransferFee(uint8,uint8,uint32)"));
  bytes4 public setTransferFeeSenderOverride = bytes4(keccak256("setTransferFeeSenderOverride(address,uint8,uint32)"));
  bytes4 public setTransferFeeReceiverOverride = bytes4(keccak256("setTransferFeeReceiverOverride(uint8,address,uint32)"));
  bytes4 public setPortfolioStatus = bytes4(keccak256("setPortfolioStatus(address,bool)"));
  bytes4 public setTreasury = bytes4(keccak256("setTreasury(address)"));

  // Entity operations
  bytes4 public entityTransfer = bytes4(keccak256("transfer(address,uint256)"));
  bytes4 public entityTransferWithOverrides = bytes4(keccak256("transferWithOverrides(address,uint256)"));
  bytes4 public setOrgId = bytes4(keccak256("setOrgId(bytes32)"));
  bytes4 public setManager = bytes4(keccak256("setManager(address)"));
  bytes4 public payout = bytes4(keccak256("payout(address,uint256)"));
  bytes4 public payoutWithOverrides = bytes4(keccak256("payoutWithOverrides(address,uint256)"));

  // Portfolio operations
  bytes4 public setRedemptionFee = bytes4(keccak256("setRedemptionFee(uint256)"));
  bytes4 public setCap = bytes4(keccak256("setCap(uint256)"));
  bytes4 public portfolioDeposit = bytes4(keccak256("portfolioDeposit(address,uint256,bytes)"));
  bytes4 public portfolioRedeem = bytes4(keccak256("portfolioRedeem(address,uint256,bytes)"));

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

    // role 1: P_01	Payout capability from entities
    globalTestRegistry.setRoleCapability(1, orgTarget, payout, true);
    globalTestRegistry.setRoleCapability(1, fundTarget, payout, true);
    globalTestRegistry.setRoleCapability(1, orgTarget, payoutWithOverrides, true);
    globalTestRegistry.setRoleCapability(1, fundTarget, payoutWithOverrides, true);
    globalTestRegistry.setUserRole(capitalCommittee, 1, true);

    // role 2: P_02	Transfer balances between entities
    globalTestRegistry.setRoleCapability(2, orgTarget, entityTransfer, true);
    globalTestRegistry.setRoleCapability(2, fundTarget, entityTransfer, true);
    globalTestRegistry.setRoleCapability(2, orgTarget, entityTransferWithOverrides, true);
    globalTestRegistry.setRoleCapability(2, fundTarget, entityTransferWithOverrides, true);
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
    globalTestRegistry.setRoleCapability(8, address(globalTestRegistry), setDefaultPayoutFee, true);
    globalTestRegistry.setUserRole(programCommittee, 8, true);

    // role 10: P_10 Change portfolio Management Fee
    globalTestRegistry.setRoleCapability(10, portfolioTarget, setRedemptionFee, true);
    globalTestRegistry.setUserRole(programCommittee, 10, true);

    // role 11: P_11 Change entity's outbound/inbound override fees
    globalTestRegistry.setRoleCapability(11, address(globalTestRegistry), setDonationFeeReceiverOverride, true);
    globalTestRegistry.setRoleCapability(11, address(globalTestRegistry), setPayoutFeeOverride, true);
    globalTestRegistry.setRoleCapability(11, address(globalTestRegistry), setTransferFeeSenderOverride, true);
    globalTestRegistry.setRoleCapability(11, address(globalTestRegistry), setTransferFeeReceiverOverride, true);
    globalTestRegistry.setUserRole(programCommittee, 11, true);

    // role 12: P_12 Enable a new portfolio
    globalTestRegistry.setRoleCapability(12, address(globalTestRegistry), setPortfolioStatus, true);
    globalTestRegistry.setUserRole(investmentCommittee, 12, true);

    // role 13: P_13 Enter and exit an entity balance to and from a portfolio
    globalTestRegistry.setRoleCapability(13, fundTarget, portfolioDeposit, true);
    globalTestRegistry.setRoleCapability(13, orgTarget, portfolioDeposit, true);
    globalTestRegistry.setRoleCapability(13, fundTarget, portfolioRedeem, true);
    globalTestRegistry.setRoleCapability(13, orgTarget, portfolioRedeem, true);
    globalTestRegistry.setUserRole(investmentCommittee, 13, true);

    // role 14: P_14 Change portfolio cap
    globalTestRegistry.setRoleCapability(14, portfolioTarget, setCap, true);
    globalTestRegistry.setUserRole(investmentCommittee, 14, true);
    
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

  // local helper function to set an entity's contract balance and token balance
  function _setEntityBalance(Entity _entity, uint256 _newBalance) internal {
      stdstore
          .target(address(_entity))
          .sig(_entity.balance.selector)
          .checked_write(_newBalance);
      ERC20 _baseToken = globalTestRegistry.baseToken();
      deal(address(_baseToken), address(_entity), _newBalance);
  }

  // local helper function to set an entity's contract balance
  function _setEntityContractBalance(Entity _entity, uint256 _newBalance) internal {
      stdstore
          .target(address(_entity))
          .sig(_entity.balance.selector)
          .checked_write(_newBalance);
  }
}
