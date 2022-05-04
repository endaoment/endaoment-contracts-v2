// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import { Math } from "../lib/Math.sol";
import { EntityInactive, InsufficientFunds, InvalidAction, InvalidTransferAttempt } from "../Entity.sol";
import { OrgFundFactory } from "../OrgFundFactory.sol";
import { Fund } from "../Fund.sol";
import { Org } from "../Org.sol";

import "forge-std/Test.sol";

contract EntitySetManager is DeployTest {
    address[] public actors = [board, capitalCommittee];

    event EntityManagerSet(address indexed oldManager, address indexed newManager);

    function testFuzz_SetManagerSuccess(address _manager, address _newManager) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.expectEmit(true, false, false, false);
        emit EntityManagerSet(_manager, _newManager);
        vm.prank(_manager);
        _fund.setManager(_newManager);
        assertEq(_fund.manager(), _newManager);
    }

    function testFuzz_SetManagerAsRole(address _newManager, uint _actor) public {
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(self, "salt");
        vm.expectEmit(true, true, false, false);
        emit EntityManagerSet(self, _newManager);
        vm.prank(actor);
        _fund.setManager(_newManager);
        assertEq(_fund.manager(), _newManager);
    }

    function testFuzz_SetManagerFail(address _manager, address _newManager) public {
        vm.assume(_manager != self);
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.expectRevert(Unauthorized.selector);
        _fund.setManager(_newManager);
    } 
}

// This abstract test contract acts as a harness to test common features of all Entity types.
// Concrete test contracts that inherit from contract to test a specific entity type need only set the Entity type
//  to be tested and deploy their specific entity to be subjected to the tests.
abstract contract EntityDonateTransferTest is DeployTest {
    using stdStorage for StdStorage;
    Entity entity;
    Entity receivingEntity;
    uint8 testEntityType;
    uint32 internal constant onePercentZoc = 100;

    event EntityDonationReceived(address indexed from, address indexed to, uint256 amount, uint256 fee);
    event EntityFundsTransferred(address indexed from, address indexed to, uint256 amountReceived, uint256 amountFee);
    event EntityBalanceReconciled(address indexed entity, uint256 amountReceived, uint256 amountFee);

    // local helper function to pick a receiving entity type for transfers, given an _entityType from the fuzzer
    //  (sets the instance variable receivingEntity as a side-effect)
    function _deployEntity(uint8 _entityType, address _manager) internal returns (uint8) {
        uint8 _receivingType = uint8(bound(_entityType, OrgType, FundType));
        if (_receivingType == OrgType) {
            receivingEntity = orgFundFactory.deployOrg("someReceivingOrgId", "salt");
            vm.prank(board);
            receivingEntity.setManager(_manager);
        } else {
            receivingEntity = orgFundFactory.deployFund(_manager, "salt");
        }
        return _receivingType;
    }

    // Test a normal donation to an entity from a donor.
    function testFuzz_DonateSuccess(address _donor, uint256 _donationAmount, uint256 _feePercent) public {
        _donationAmount = bound(_donationAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        vm.assume(_donor != treasury);
        vm.assume(_donor != address(entity));
        _feePercent = bound(_feePercent, 0, Math.ZOC);
        vm.prank(board);
        // set the default donation fee to some percentage between 0 and 100 percent
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_donor);
        _baseToken.approve(address(entity), _donationAmount);
        uint256 _amountFee = Math.zocmul(_donationAmount, _feePercent);
        uint256 _amountReceived = _donationAmount - _amountFee;
        vm.expectEmit(true, true, false, true);
        emit EntityDonationReceived(_donor, address(entity), _donationAmount, _amountFee);
        deal(address(_baseToken), _donor, _donationAmount);
        vm.prank(_donor);
        entity.donate(_donationAmount);
        assertEq(_baseToken.balanceOf(_donor), 0);
        assertEq(_baseToken.balanceOf(address(entity)), _amountReceived);
        assertEq(entity.balance(), _amountReceived);
        assertEq(_baseToken.balanceOf(treasury), _amountFee);
    }

    // Test a donation with overrides to an entity from a donor.
    function testFuzz_DonateWithOverridesSuccess(address _donor, uint256 _donationAmount, uint256 _feePercent) public {
        _donationAmount = bound(_donationAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        vm.assume(_donor != treasury);
        vm.assume(_donor != address(entity));
        _feePercent = bound(_feePercent, onePercentZoc, Math.ZOC);
        vm.startPrank(board);
        // set the default donation fee to some percentage between 1 and 100 percent
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        // set the donation receiver override fee to one percent less than the default fee percentage
        globalTestRegistry.setDonationFeeReceiverOverride(entity, uint32(_feePercent - onePercentZoc));
        vm.stopPrank();
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_donor);
        _baseToken.approve(address(entity), _donationAmount);
        uint256 _amountFee = Math.zocmul(_donationAmount, _feePercent - onePercentZoc);
        uint256 _amountReceived = _donationAmount - _amountFee;
        vm.expectEmit(true, true, false, true);
        emit EntityDonationReceived(_donor, address(entity), _donationAmount, _amountFee);
        deal(address(_baseToken), _donor, _donationAmount);
        vm.prank(_donor);
        entity.donateWithOverrides(_donationAmount);
        assertEq(_baseToken.balanceOf(_donor), 0);
        assertEq(_baseToken.balanceOf(address(entity)), _amountReceived);
        assertEq(entity.balance(), _amountReceived);
        assertEq(_baseToken.balanceOf(treasury), _amountFee);
    }

    // Test that a donation to an entity that has donations disallowed via default donation fee fails.
    function testFuzz_DonateFailInvalidAction(address _donor, uint256 _donationAmount) public {
        vm.prank(board);
        // disallow donations to the entityType by setting the default donation fee to max
        globalTestRegistry.setDefaultDonationFee(testEntityType, type(uint32).max);
        vm.expectRevert(InvalidAction.selector);
        vm.prank(_donor);
        entity.donate(_donationAmount);
    }

    // Test that a donation to an inactive Entity fails.
    function testFuzz_DonateFailInactive(address _donor, uint256 _donationAmount) public {
        vm.prank(board);
        globalTestRegistry.setEntityStatus(entity, false);
        vm.expectRevert(abi.encodeWithSelector(EntityInactive.selector));
        vm.prank(_donor);
        entity.donate(_donationAmount);
    }

    // Test that a donation with fee overrides to an entity that has donations disallowed via default donation fee fails.
    function testFuzz_DonateWithOverridesFailInvalidAction(address _donor, uint256 _donationAmount) public {
        vm.prank(board);
        // disallow donations to the entityType by setting the default donation fee to max
        globalTestRegistry.setDefaultDonationFee(testEntityType, type(uint32).max);
        vm.expectRevert(InvalidAction.selector);
        vm.prank(_donor);
        entity.donateWithOverrides(_donationAmount);
    }

    // Test that a donation with fee overrides to an inactive Entity fails.
    function testFuzz_DonateWithOverridesFailInactive(address _donor, uint256 _donationAmount) public {
        vm.prank(board);
        globalTestRegistry.setEntityStatus(entity, false);
        vm.expectRevert(abi.encodeWithSelector(EntityInactive.selector));
        vm.prank(_donor);
        entity.donateWithOverrides(_donationAmount);
    }

    // Test a valid transfer between 2 entities
    function testFuzz_TransferSuccess(address _manager, uint256 _amount, uint256 _feePercent, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        _amount = bound(_amount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC);
        // get the receiving entity type from the fuzzed parameter
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_manager);
        _baseToken.approve(address(entity), _amount);
        // set the default transfer fee between the 2 entity types to some percentage between 0 and 100 percent
        vm.startPrank(board);
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, uint32(_feePercent));
        entity.setManager(_manager);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        uint256 _amountFee = Math.zocmul(_amount, _feePercent);
        uint256 _amountReceived = _amount - _amountFee;
        vm.expectEmit(true, true, false, true);
        emit EntityFundsTransferred(address(entity), address(receivingEntity), _amount, _amountFee);
        vm.prank(_manager);
        entity.transfer(receivingEntity, _amount);
        assertEq(_baseToken.balanceOf(address(entity)), 0);
        assertEq(entity.balance(), 0);
        assertEq(_baseToken.balanceOf(address(receivingEntity)), _amountReceived);
        assertEq(receivingEntity.balance(), _amountReceived);
        assertEq(_baseToken.balanceOf(treasury), _amountFee);
    }

    // Test a valid transfer with sender override between 2 entities
    function testFuzz_TransferWithSenderOverrideSuccess(address _manager, uint256 _amount, uint256 _feePercent, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        _amount = bound(_amount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _feePercent = bound(_feePercent, onePercentZoc, Math.ZOC);
        // get the receiving entity type from the fuzzed parameter
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_manager);
        _baseToken.approve(address(entity), _amount);
        vm.startPrank(board);
        // set the default transfer fee between the 2 entity types to some percentage between 1 and 100 percent
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, uint32(_feePercent));
        // set the sender override fee for the transfer to one less that the default transfer fee
        globalTestRegistry.setTransferFeeSenderOverride(entity, _receivingType, uint32(_feePercent - onePercentZoc));
        entity.setManager(_manager);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        uint256 _amountFee = Math.zocmul(_amount, _feePercent - onePercentZoc);
        uint256 _amountReceived = _amount - _amountFee;
        vm.expectEmit(true, true, false, true);
        emit EntityFundsTransferred(address(entity), address(receivingEntity), _amount, _amountFee);
        vm.prank(_manager);
        entity.transferWithOverrides(receivingEntity, _amount);
        assertEq(_baseToken.balanceOf(address(entity)), 0);
        assertEq(entity.balance(), 0);
        assertEq(_baseToken.balanceOf(address(receivingEntity)), _amountReceived);
        assertEq(receivingEntity.balance(), _amountReceived);
        assertEq(_baseToken.balanceOf(treasury), _amountFee);
    }

    // Test a valid transfer with receiver override between 2 entities
    function testFuzz_TransferWithReceiverOverrideSuccess(address _manager, uint256 _amount, uint256 _feePercent, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        _amount = bound(_amount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _feePercent = bound(_feePercent, onePercentZoc, Math.ZOC);
        // get the receiving entity type from the fuzzed parameter
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_manager);
        _baseToken.approve(address(entity), _amount);
        vm.startPrank(board);
        // set the default transfer fee between the 2 entity types to some percentage between 1 and 100 percent
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, uint32(_feePercent));
        // set the receiver override fee for the transfer to one less that the default transfer fee
        globalTestRegistry.setTransferFeeReceiverOverride(testEntityType, receivingEntity, uint32(_feePercent - onePercentZoc));
        entity.setManager(_manager);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        uint256 _amountFee = Math.zocmul(_amount, _feePercent - onePercentZoc);
        uint256 _amountReceived = _amount - _amountFee;
        vm.expectEmit(true, true, false, true);
        emit EntityFundsTransferred(address(entity), address(receivingEntity), _amount, _amountFee);
        vm.prank(_manager);
        entity.transferWithOverrides(receivingEntity, _amount);
        assertEq(_baseToken.balanceOf(address(entity)), 0);
        assertEq(entity.balance(), 0);
        assertEq(_baseToken.balanceOf(address(receivingEntity)), _amountReceived);
        assertEq(receivingEntity.balance(), _amountReceived);
        assertEq(_baseToken.balanceOf(treasury), _amountFee);
    }

    // Test that a transfer fails when the default transfer fee between the 2 entities has been set to disallow it.
    function testFuzz_TransferFailInvalidAction(address _manager, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        _setEntityBalance(entity, 10);
        vm.startPrank(board);
        // disallow donations to the fund by setting the transfer donation fee to max for the entity types
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, type(uint32).max);
        entity.setManager(_manager);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        vm.expectRevert(InvalidAction.selector);
        vm.prank(_manager);
        entity.transfer(receivingEntity, 1);
    }

    // Test that a transfer fails from an inactive Entity
    function testFuzz_TransferFailInactive(address _manager, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        vm.startPrank(board);
        entity.setManager(_manager);
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, onePercentZoc);
        globalTestRegistry.setEntityStatus(entity, false);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        vm.prank(_manager);
        vm.expectRevert(abi.encodeWithSelector(EntityInactive.selector));
        entity.transfer(receivingEntity, 1);
    }

    // Test that a transfer fails when the caller is not authorized
    function testFuzz_TransferFailUnauthorized(address _caller, address _manager, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        vm.assume(_caller != _manager);
        vm.assume(_caller != board);
        vm.assume(_caller != capitalCommittee);
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        _setEntityBalance(entity, 10);
        vm.startPrank(board);
        entity.setManager(_manager);
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, onePercentZoc);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        vm.prank(_caller);
        entity.transfer(receivingEntity, 1);
    }

    // Test that a transfer fails when the source entity of the transfer has insufficient funds
    function testFuzz_TransferFailInsufficientFunds(address _manager, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        vm.startPrank(board);
        entity.setManager(_manager);
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, onePercentZoc);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        vm.prank(_manager);
        vm.expectRevert(abi.encodeWithSelector(InsufficientFunds.selector));
        entity.transfer(receivingEntity, 1);
    }

    // Test that a transfer with overrides fails when the default transfer fee between the 2 entities has been set to disallow it.
    function testFuzz_TransferWithOverridesFailInvalidAction(address _manager, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        _setEntityBalance(entity, 10);
        vm.startPrank(board);
        // disallow donations to the fund by setting the transfer donation fee to max for the entity types
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, type(uint32).max);
        entity.setManager(_manager);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        vm.expectRevert(InvalidAction.selector);
        vm.prank(_manager);
        entity.transferWithOverrides(receivingEntity, 1);
    }

    // Test that a transfer with overrides fails from an inactive Entity
    function testFuzz_TransferWithOverridesFailInactive(address _manager, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        vm.startPrank(board);
        entity.setManager(_manager);
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, onePercentZoc);
        globalTestRegistry.setEntityStatus(entity, false);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        vm.prank(_manager);
        vm.expectRevert(abi.encodeWithSelector(EntityInactive.selector));
        entity.transferWithOverrides(receivingEntity, 1);
    }

    // Test that a transfer with overrides fails when the caller is not authorized
    function testFuzz_TransferWithOverridesFailUnauthorized(address _caller, address _manager, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        vm.assume(_caller != _manager);
        vm.assume(_caller != board);
        vm.assume(_caller != capitalCommittee);
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        _setEntityBalance(entity, 10);
        vm.startPrank(board);
        entity.setManager(_manager);
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, onePercentZoc);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        vm.prank(_caller);
        entity.transferWithOverrides(receivingEntity, 1);
    }

    // Test that a transfer with overrides fails when the source entity of the transfer has insufficient funds
    function testFuzz_TransferWithOverridesFailInsufficientFunds(address _manager, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        vm.startPrank(board);
        entity.setManager(_manager);
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, onePercentZoc);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        vm.prank(_manager);
        vm.expectRevert(abi.encodeWithSelector(InsufficientFunds.selector));
        entity.transferWithOverrides(receivingEntity, 1);
    }

    // Test that the receiveTransfer function fails if not called by another entity.
    // The 'happy path' of receiveTransfer function testing is performed above in testFuzz_TransferSuccess.
    function testFuzz_ReceiveTransferFailInvalidTransferAttempt(uint256 _transferAmount) public {
        vm.expectRevert(InvalidTransferAttempt.selector);
        vm.prank(board);
        entity.receiveTransfer(_transferAmount);
    }

    // Test that the reconcileBalance function sweeps 'rogue' baseTokens that have been deposited into the entity contract balance,
    //  and updates the balance (less default fee) and verifies that the fee has been taken from the swept amount and deposited to the treasury
    function testFuzz_ReconcileBalanceSuccess(address _manager, uint256 _balanceAmount, uint256 _sweepAmount, uint256 _feePercent) public {
        _balanceAmount = bound(_balanceAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC);
        vm.startPrank(board);
        // set the default donation fee to some percentage between 0 and 100 percent
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        entity.setManager(_manager);
        vm.stopPrank();
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _balanceAmount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        // update the token balance to be more than the entity balance so the sweep can be attempted
        deal(address(_baseToken), address(entity), _balanceAmount + _sweepAmount);
        uint256 _amountFee = Math.zocmul(_sweepAmount, _feePercent);
        uint256 _amountReceived = _sweepAmount - _amountFee;
        vm.startPrank(_manager);
        _baseToken.approve(address(entity),  _balanceAmount + _sweepAmount);
        vm.expectEmit(true, false, false, true);
        emit EntityBalanceReconciled(address(entity), _sweepAmount, _amountFee);
        entity.reconcileBalance();
        assertEq(_baseToken.balanceOf(treasury), _amountFee);
        assertEq(entity.balance(), _balanceAmount + _amountReceived);
        vm.stopPrank();
    }

    // Test that the reconcileBalance function sweeps 'rogue' baseTokens that have been deposited into the entity contract balance,
    //  and updates the balance (less override fee) and verifies that the fee has been taken from the swept amount and deposited to the treasury
    function testFuzz_ReconcileBalanceWithOverrideSuccess(address _manager, uint256 _balanceAmount, uint256 _sweepAmount, uint256 _feePercent) public {
        _balanceAmount = bound(_balanceAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _feePercent = bound(_feePercent, onePercentZoc, Math.ZOC);
        vm.startPrank(board);
        // set the default donation fee to some percentage between 1 and 100 percent
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        // set the donation override fee to one percent less than the default fee percentage
        globalTestRegistry.setDonationFeeReceiverOverride(entity, uint32(_feePercent - onePercentZoc));
        entity.setManager(_manager);
        vm.stopPrank();
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _balanceAmount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        // update the token balance to be more than the entity balance so the sweep can be attempted
        deal(address(_baseToken), address(entity), _balanceAmount + _sweepAmount);
        uint256 _amountFee = Math.zocmul(_sweepAmount, _feePercent - onePercentZoc);
        uint256 _amountReceived = _sweepAmount - _amountFee;
        vm.startPrank(_manager);
        _baseToken.approve(address(entity),  _balanceAmount + _sweepAmount);
        vm.expectEmit(true, false, false, true);
        emit EntityBalanceReconciled(address(entity), _sweepAmount, _amountFee);
        entity.reconcileBalance();
        assertEq(_baseToken.balanceOf(treasury), _amountFee);
        assertEq(entity.balance(), _balanceAmount + _amountReceived);
        vm.stopPrank();
    }

    // Test that the reconcileBalance function emits an appropriate event when there are no 'rogue' baseTokens to be swept into the contract balance.
    function testFuzz_ReconcileBalanceSuccessNoTokens(address _manager, uint256 _balanceAmount, uint256 _feePercent) public {
        _balanceAmount = bound(_balanceAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC);
        vm.startPrank(board);
        // set the default donation fee to some percentage between 0 and 100 percent
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        entity.setManager(_manager);
        vm.stopPrank();
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _balanceAmount);
        vm.startPrank(_manager);
        vm.expectEmit(true, false, false, true);
        emit EntityBalanceReconciled(address(entity), 0, 0);
        entity.reconcileBalance();
        ERC20 _baseToken = globalTestRegistry.baseToken();
        assertEq(_baseToken.balanceOf(treasury), 0);
        assertEq(entity.balance(), _balanceAmount);
        vm.stopPrank();
    }

    // Test that the reconcileBalance function fails when the entity donations disallowed via default donation fee setting.
    function testFuzz_ReconcileBalanceFailInvalidAction(address _manager, uint256 _balanceAmount, uint256 _sweepAmount) public {
        _balanceAmount = bound(_balanceAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        vm.startPrank(board);
        // set the default donation fee to some percentage between 0 and 100 percent
        globalTestRegistry.setDefaultDonationFee(testEntityType, type(uint32).max);
        entity.setManager(_manager);
        vm.stopPrank();
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _balanceAmount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        // update the token balance to be more than the entity balance so the sweep can be attempted
        deal(address(_baseToken), address(entity), _balanceAmount + _sweepAmount);
        vm.startPrank(_manager);
        _baseToken.approve(address(entity),  _balanceAmount + _sweepAmount);
        vm.expectRevert(InvalidAction.selector);
        entity.reconcileBalance();
        vm.stopPrank();
    }

    // Test that the reconcileBalance function fails if not called by the entity manager.
    function testFuzz_ReconcileBalanceFailsUnauthorized(address _manager) public {
        vm.prank(board);
        entity.setManager(_manager);
        vm.expectRevert(Unauthorized.selector);
        vm.prank(user1);
        entity.reconcileBalance();
    }
}

contract OrgDonateTransferTest is EntityDonateTransferTest {
    // this will run all tests in EntityDonateTransferTest
    function setUp() public override {
        super.setUp();
        entity = orgFundFactory.deployOrg("someOrgId", "someSalt");
        testEntityType = OrgType;
    }
}

contract FundDonateTransferTest is EntityDonateTransferTest {
    // this will run all tests in EntityDonateTransferTest
    function setUp() public override {
        super.setUp();
        entity = orgFundFactory.deployFund(address(0x1111), "someSalt");
        testEntityType = FundType;
    }
}
