    // SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import {Registry} from "./Registry.sol";
import {NDAO} from "./NDAO.sol";
import {NVT, INDAO} from "./NVT.sol";
import {RollingMerkleDistributor} from "./RollingMerkleDistributor.sol";
import {Portfolio} from "./Portfolio.sol";
import {Entity} from "./Entity.sol";
import {Org} from "./Org.sol";

/**
 * @notice Roles and Capabilities Control - This sets up the the Role/Capability authorizations.
 */
contract RolesAndCapabilitiesControl {
    // special targets for auth permissions
    address orgTarget = address(bytes20(bytes.concat("entity", bytes1(uint8(1)))));
    address fundTarget = address(bytes20(bytes.concat("entity", bytes1(uint8(2)))));
    address portfolioTarget = address(bytes20("portfolio"));

    // Registry operations
    bytes4 public setEntityStatus = Registry.setEntityStatus.selector;
    bytes4 public setDefaultDonationFee = Registry.setDefaultDonationFee.selector;
    bytes4 public setDonationFeeReceiverOverride = Registry.setDonationFeeReceiverOverride.selector;
    bytes4 public setDefaultPayoutFee = Registry.setDefaultPayoutFee.selector;
    bytes4 public setPayoutFeeOverride = Registry.setPayoutFeeOverride.selector;
    bytes4 public setDefaultTransferFee = Registry.setDefaultTransferFee.selector;
    bytes4 public setTransferFeeSenderOverride = Registry.setTransferFeeSenderOverride.selector;
    bytes4 public setTransferFeeReceiverOverride = Registry.setTransferFeeReceiverOverride.selector;
    bytes4 public setPortfolioStatus = Registry.setPortfolioStatus.selector;
    bytes4 public setTreasury = Registry.setTreasury.selector;
    bytes4 public setSwapWrapperStatus = Registry.setSwapWrapperStatus.selector;
    bytes4 public setFactoryApproval = Registry.setFactoryApproval.selector;

    // Entity operations
    bytes4 public donateWithAdminOverrides = Entity.donateWithAdminOverrides.selector;
    bytes4 public entityTransferToEntity = Entity.transferToEntity.selector;
    bytes4 public entityTransferToEntityWithOverrides = Entity.transferToEntityWithOverrides.selector;
    bytes4 public entityTransferToEntityWithAdminOverrides = Entity.transferToEntityWithAdminOverrides.selector;
    bytes4 public swapAndReconcileBalance = Entity.swapAndReconcileBalance.selector;
    bytes4 public setManager = Entity.setManager.selector;
    bytes4 public payout = Entity.payout.selector;
    bytes4 public payoutWithOverrides = Entity.payoutWithOverrides.selector;
    bytes4 public payoutWithAdminOverrides = Entity.payoutWithAdminOverrides.selector;
    bytes4 public portfolioDeposit = Entity.portfolioDeposit.selector;
    bytes4 public portfolioRedeem = Entity.portfolioRedeem.selector;

    // Org operations
    bytes4 public setOrgId = Org.setOrgId.selector;

    // Portfolio operations
    bytes4 public setDepositFee = Portfolio.setDepositFee.selector;
    bytes4 public setRedemptionFee = Portfolio.setRedemptionFee.selector;
    bytes4 public setCap = Portfolio.setCap.selector;
    bytes4 public takeFees = Portfolio.takeFees.selector;

    // NDAO operations
    bytes4 public ndaoMint = NDAO.mint.selector;

    // NVT operations
    bytes4 public nvtVestLock = NVT.vestLock.selector;
    bytes4 public nvtClawback = NVT.clawback.selector;

    // Rolling Merkle Distributor operations
    bytes4 public rollover = RollingMerkleDistributor.rollover.selector;

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
        setCoreRolesAndCapabilities(_registry, _capitalCommittee, _programCommittee, _investmentCommittee, _tokenTrust);
        setTokenRolesAndCapabilities(
            _registry,
            _capitalCommittee,
            _programCommittee,
            _investmentCommittee,
            _tokenTrust,
            _ndao,
            _nvt,
            _distributor,
            _baseDistributor
        );
    }

    function setCoreRolesAndCapabilities(
        Registry _registry,
        address _capitalCommittee,
        address _programCommittee,
        address _investmentCommittee,
        address /* _tokenTrust */
    ) public {
        // role 1: P_01	Payout capability from entities
        _registry.setRoleCapability(1, orgTarget, payout, true);
        _registry.setRoleCapability(1, fundTarget, payout, true);
        _registry.setRoleCapability(1, orgTarget, payoutWithOverrides, true);
        _registry.setRoleCapability(1, fundTarget, payoutWithOverrides, true);
        _registry.setRoleCapability(1, orgTarget, payoutWithAdminOverrides, true);
        _registry.setRoleCapability(1, fundTarget, payoutWithAdminOverrides, true);
        _registry.setUserRole(_capitalCommittee, 1, true);

        // role 2: P_02	Transfer balances between entities
        _registry.setRoleCapability(2, orgTarget, entityTransferToEntity, true);
        _registry.setRoleCapability(2, fundTarget, entityTransferToEntity, true);
        _registry.setRoleCapability(2, orgTarget, entityTransferToEntityWithOverrides, true);
        _registry.setRoleCapability(2, fundTarget, entityTransferToEntityWithOverrides, true);
        _registry.setRoleCapability(2, orgTarget, entityTransferToEntityWithAdminOverrides, true);
        _registry.setRoleCapability(2, fundTarget, entityTransferToEntityWithAdminOverrides, true);
        _registry.setUserRole(_capitalCommittee, 2, true);

        // role 3: P_03 Liquidate assets in an entity
        _registry.setRoleCapability(3, orgTarget, swapAndReconcileBalance, true);
        _registry.setRoleCapability(3, fundTarget, swapAndReconcileBalance, true);
        _registry.setUserRole(_capitalCommittee, 3, true);

        // role 4: P_04 Send USDC from Org Treasury (No treasury contract -- could be multisig)

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

        // role 9: P_09 Change portfolio entry/exit fees
        _registry.setRoleCapability(9, portfolioTarget, setDepositFee, true);
        _registry.setRoleCapability(9, portfolioTarget, setRedemptionFee, true);
        _registry.setUserRole(_programCommittee, 9, true);

        // role 10: P_10 Take fees
        _registry.setRoleCapability(10, portfolioTarget, takeFees, true);
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

        // role 15: P_15 Pause entrance to a portfolio (defunct -- to pause, set portfolio cap to 0)

        // role 16: P_16 Change base token (defunct -- no changing of baseToken)

        // roles 17 & 18 are set below in `setRolesAndCapabilitiesToken`

        // role 19: P_19 Donate with admin fee override
        _registry.setRoleCapability(19, orgTarget, donateWithAdminOverrides, true);
        _registry.setRoleCapability(19, fundTarget, donateWithAdminOverrides, true);
        _registry.setUserRole(_capitalCommittee, 19, true);

        // role 20: P_20 Enable/disable swap wrapper
        _registry.setRoleCapability(20, address(_registry), setSwapWrapperStatus, true);
        _registry.setUserRole(_capitalCommittee, 20, true);

        // role 21: P_21 Not Present in FR spreadsheet

        // roles 22 & 23 are set below in `setRolesAndCapabilitiesToken`

        // role 24: P_24 Set admin treasury address (board only)
        _registry.setRoleCapability(24, address(_registry), setTreasury, true);

        // role 25: P_25 Enable/disable entity factories
        _registry.setRoleCapability(25, address(_registry), setFactoryApproval, true);
    }

    function setTokenRolesAndCapabilities(
        Registry _registry,
        address _capitalCommittee,
        address, /* _programCommittee */
        address, /* _investmentCommittee */
        address _tokenTrust,
        NDAO _ndao,
        NVT _nvt,
        RollingMerkleDistributor _distributor,
        RollingMerkleDistributor _baseDistributor
    ) public {
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
