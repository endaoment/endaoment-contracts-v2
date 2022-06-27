  // SPDX-License-Identifier: BSD 3-Claused
pragma solidity 0.8.13;

import { Registry } from "./Registry.sol";
import { NDAO } from "./NDAO.sol";
import { NVT, INDAO } from "./NVT.sol";
import { RollingMerkleDistributor } from "./RollingMerkleDistributor.sol";

/**
 * @notice Roles and Capabilities Control - This sets up the the Role/Capability authorizations.
 */
contract RolesAndCapabilitiesControl {
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

    /**
     * @notice Setup the proper roles and capabilities for the capitalCommittee, programCommittee, investmentCommittee, and tokenTrust.
     * @dev This function is called both by the test environment (DeployTest) and the deploy script (Deploy).
     */
    function setRolesAndCapabilities(
        Registry _registry,
        address _capitalCommittee,
        address _programCommittee,
        address _investmentCommittee,
        address _tokenTrust,
        NDAO _ndao,
        NVT _nvt,
        RollingMerkleDistributor _distributor,
        RollingMerkleDistributor _baseDistributor
    ) public {
        // role 1: P_01	Payout capability from entities
        _registry.setRoleCapability(1, orgTarget, payout, true);
        _registry.setRoleCapability(1, fundTarget, payout, true);
        _registry.setRoleCapability(1, orgTarget, payoutWithOverrides, true);
        _registry.setRoleCapability(1, fundTarget, payoutWithOverrides, true);
        _registry.setUserRole(_capitalCommittee, 1, true);

        // role 2: P_02	Transfer balances between entities
        _registry.setRoleCapability(2, orgTarget, entityTransfer, true);
        _registry.setRoleCapability(2, fundTarget, entityTransfer, true);
        _registry.setRoleCapability(2, orgTarget, entityTransferWithOverrides, true);
        _registry.setRoleCapability(2, fundTarget, entityTransferWithOverrides, true);
        _registry.setUserRole(_capitalCommittee, 2, true);

        // role 5: P_05	Enable/disable entities
        _registry.setRoleCapability(5, address(_registry), setEntityStatus, true);
        _registry.setUserRole(_capitalCommittee, 5, true);

        // role 6: P_06	Change an org's TaxID
        _registry.setRoleCapability(6, orgTarget, setOrgId, true);
        _registry.setUserRole(_capitalCommittee, 6, true);

        // role 7: P_07	Change entity's manager address
        _registry.setRoleCapability(7, orgTarget, setManager, true);
        _registry.setRoleCapability(7, fundTarget, setManager, true);
        _registry.setUserRole(_capitalCommittee, 7, true);

        // role 8: P_08 Change entity's fees
        _registry.setRoleCapability(8, address(_registry), setDefaultDonationFee, true);
        _registry.setRoleCapability(8, address(_registry), setDefaultTransferFee, true);
        _registry.setRoleCapability(8, address(_registry), setDefaultPayoutFee, true);
        _registry.setUserRole(_programCommittee, 8, true);

        // role 10: P_10 Change portfolio Management Fee
        _registry.setRoleCapability(10, portfolioTarget, setRedemptionFee, true);
        _registry.setUserRole(_programCommittee, 10, true);

        // role 11: P_11 Change entity's outbound/inbound override fees
        _registry.setRoleCapability(11, address(_registry), setDonationFeeReceiverOverride, true);
        _registry.setRoleCapability(11, address(_registry), setPayoutFeeOverride, true);
        _registry.setRoleCapability(11, address(_registry), setTransferFeeSenderOverride, true);
        _registry.setRoleCapability(11, address(_registry), setTransferFeeReceiverOverride, true);
        _registry.setUserRole(_programCommittee, 11, true);

        // role 12: P_12 Enable a new portfolio
        _registry.setRoleCapability(12, address(_registry), setPortfolioStatus, true);
        _registry.setUserRole(_investmentCommittee, 12, true);

        // role 13: P_13 Enter and exit an entity balance to and from a portfolio
        _registry.setRoleCapability(13, fundTarget, portfolioDeposit, true);
        _registry.setRoleCapability(13, orgTarget, portfolioDeposit, true);
        _registry.setRoleCapability(13, fundTarget, portfolioRedeem, true);
        _registry.setRoleCapability(13, orgTarget, portfolioRedeem, true);
        _registry.setUserRole(_investmentCommittee, 13, true);

        // role 14: P_14 Change portfolio cap
        _registry.setRoleCapability(14, portfolioTarget, setCap, true);
        _registry.setUserRole(_investmentCommittee, 14, true);
        
        // role 17: P_17 NDAO Rolling Merkle Distributor Rollover
        _registry.setRoleCapability(17, address(_distributor), rollover, true);
        _registry.setUserRole(_tokenTrust, 17, true);

        // role 18: P_18 Base Token Rolling Merkle Distributor Rollover
        _registry.setRoleCapability(18, address(_baseDistributor), rollover, true);
        _registry.setUserRole(_tokenTrust, 18, true);

        // role 22: P_22 Mint NDAO
        _registry.setRoleCapability(22, address(_ndao), ndaoMint, true);
        _registry.setUserRole(_capitalCommittee, 22, true);

        // role 23: P_23 NVT Vesting & Clawback
        _registry.setRoleCapability(23, address(_nvt), nvtVestLock, true);
        _registry.setRoleCapability(23, address(_nvt), nvtClawback, true);
        _registry.setUserRole(_capitalCommittee, 23, true);
    }
}