// SPDX-License-Identifier: BSD 3-Claused
pragma solidity 0.8.13;
import "./utils/DeployTest.sol";
import { MockSwapperTestHarness } from "./utils/MockSwapperTestHarness.sol";
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

contract EntityHarness is MockSwapperTestHarness {
    Entity receivingEntity;

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
}

// This abstract test contract acts as a harness to test common features of all Entity types.
// Concrete test contracts that inherit from contract to test a specific entity type need only set the Entity type
//  to be tested and deploy their specific entity to be subjected to the tests.
abstract contract EntityTokenTransactionTest is EntityHarness {
    using stdStorage for StdStorage;
    Entity entity;
    uint8 testEntityType;
    uint32 internal constant onePercentZoc = 100;
    address[] public payoutActors = [board, capitalCommittee];

    event EntityDonationReceived(address indexed from, address indexed to, uint256 amount, uint256 fee);
    event EntityFundsTransferred(address indexed from, address indexed to, uint256 amountReceived, uint256 amountFee);
    event EntityBalanceReconciled(address indexed entity, uint256 amountReceived, uint256 amountFee);
    event EntityBalanceCorrected(address indexed entity, uint256 newBalance);
    event EntityFundsPaidOut(address indexed from, address indexed to, uint256 amountSent, uint256 amountFee);

    // Test a normal donation to an entity from a donor.
    function testFuzz_DonateSuccess(address _donor, uint256 _donationAmount, uint256 _feePercent, bool _isActive) public {
        _donationAmount = bound(_donationAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        vm.assume(_donor != treasury);
        vm.assume(_donor != address(entity));
        _feePercent = bound(_feePercent, 0, Math.ZOC);
        vm.startPrank(board);
        globalTestRegistry.setEntityStatus(entity, _isActive);
        // set the default donation fee to some percentage between 0 and 100 percent
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.stopPrank();
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
    function testFuzz_DonateWithOverridesSuccess(address _donor, uint256 _donationAmount, uint256 _feePercent, bool _isActive) public {
        _donationAmount = bound(_donationAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        vm.assume(_donor != treasury);
        vm.assume(_donor != address(entity));
        _feePercent = bound(_feePercent, onePercentZoc, Math.ZOC);
        vm.startPrank(board);
        globalTestRegistry.setEntityStatus(entity, _isActive);
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

    // Test that a donation with fee overrides to an entity that has donations disallowed via default donation fee fails.
    function testFuzz_DonateWithOverridesFailInvalidAction(address _donor, uint256 _donationAmount) public {
        vm.prank(board);
        // disallow donations to the entityType by setting the default donation fee to max
        globalTestRegistry.setDefaultDonationFee(testEntityType, type(uint32).max);
        vm.expectRevert(InvalidAction.selector);
        vm.prank(_donor);
        entity.donateWithOverrides(_donationAmount);
    }

    // Test a valid payout from an entity to an address
    function testFuzz_PayoutSuccess(address _receiver, uint256 _amount, uint256 _feePercent, uint _actorIndex, bool _isActive) public {
        vm.assume(address(entity) != _receiver);
        vm.assume(treasury != _receiver);
        address _actor = payoutActors[_actorIndex % payoutActors.length];
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.startPrank(board);
        globalTestRegistry.setEntityStatus(entity, _isActive);
        globalTestRegistry.setDefaultPayoutFee(testEntityType, uint32(_feePercent));
        vm.stopPrank();
        uint256 _amountFee = Math.zocmul(_amount, _feePercent);
        uint256 _amountSent = _amount - _amountFee;
        vm.expectEmit(true, true, false, true);
        emit EntityFundsPaidOut(address(entity), _receiver, _amount, _amountFee);
        vm.prank(_actor);
        entity.payout(_receiver, _amount);
        assertEq(_baseToken.balanceOf(address(entity)), 0);
        assertEq(entity.balance(), 0);
        assertEq(_baseToken.balanceOf(address(_receiver)), _amountSent);
        assertEq(_baseToken.balanceOf(treasury), _amountFee);
    }

    // Test a valid payout with sender override from an entity to an address
    function testFuzz_PayoutWithOverridesSuccess(address _receiver, uint256 _amount, uint256 _feePercent, uint _actorIndex, bool _isActive) public {
        vm.assume(address(entity) != _receiver);
        vm.assume(treasury != _receiver);
        address _actor = payoutActors[_actorIndex % payoutActors.length];
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, onePercentZoc, Math.ZOC);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.startPrank(board);
        globalTestRegistry.setEntityStatus(entity, _isActive);
        globalTestRegistry.setDefaultPayoutFee(testEntityType, uint32(_feePercent));
        globalTestRegistry.setPayoutFeeOverride(entity, uint32(_feePercent - onePercentZoc));
        vm.stopPrank();
        uint256 _amountFee = Math.zocmul(_amount, _feePercent - onePercentZoc);
        uint256 _amountSent = _amount - _amountFee;
        vm.expectEmit(true, true, false, true);
        emit EntityFundsPaidOut(address(entity), _receiver, _amount, _amountFee);
        vm.prank(_actor);
        entity.payoutWithOverrides(_receiver, _amount);
        assertEq(_baseToken.balanceOf(address(entity)), 0);
        assertEq(entity.balance(), 0);
        assertEq(_baseToken.balanceOf(address(_receiver)), _amountSent);
        assertEq(_baseToken.balanceOf(treasury), _amountFee);
    }

    // Test that a payout fails when the default payout fee has been set to disallow it.
    function testFuzz_PayoutFailInvalidAction(address _receiver, uint256 _amount, uint _actorIndex) public {
        address _actor = payoutActors[_actorIndex % payoutActors.length];
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_actor);
        _baseToken.approve(address(entity), _amount);
        // set the default payout fee for the entity type to the max to disallow the payout
        vm.prank(board);
        globalTestRegistry.setDefaultPayoutFee(testEntityType, type(uint32).max);
        vm.expectRevert(InvalidAction.selector);
        vm.prank(_actor);
        entity.payout(_receiver, _amount);
    }

    // Test that a payout fails when the caller is not authorized.
    function testFuzz_PayoutFailUnauthorized(address _receiver, uint256 _amount, uint _actorIndex) public {
        address _actor = payoutActors[_actorIndex % payoutActors.length];
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_actor);
        _baseToken.approve(address(entity), _amount);
        // set the default payout fee for the entity type to the max to disallow the payout
        vm.prank(board);
        globalTestRegistry.setDefaultPayoutFee(testEntityType, onePercentZoc);
        vm.expectRevert(Unauthorized.selector);
        vm.prank(user1);
        entity.payout(_receiver, _amount);
    }

    // Test that a payout fails when the source entity of the transfer has insufficient funds.
    function testFuzz_PayoutFailInsufficientFunds(address _receiver, uint256 _amount, uint _actorIndex) public {
        address _actor = payoutActors[_actorIndex % payoutActors.length];
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        // set the default payout fee for the entity type to the max to disallow the payout
        vm.prank(board);
        globalTestRegistry.setDefaultPayoutFee(testEntityType, onePercentZoc);
        vm.expectRevert(InsufficientFunds.selector);
        vm.prank(_actor);
        entity.payout(_receiver, _amount);
    }

    // Test that a payout with override fails when the default payout fee has been set to disallow it.
    function testFuzz_PayoutWithOverridesFailInvalidAction(address _receiver, uint256 _amount, uint _actorIndex) public {
        address _actor = payoutActors[_actorIndex % payoutActors.length];
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_actor);
        _baseToken.approve(address(entity), _amount);
        // set the default payout fee for the entity type to the max to disallow the payout
        vm.prank(board);
        globalTestRegistry.setDefaultPayoutFee(testEntityType, type(uint32).max);
        vm.expectRevert(InvalidAction.selector);
        vm.prank(_actor);
        entity.payoutWithOverrides(_receiver, _amount);
    }

    // Test that a payout with override fails when the caller is not authorized.
    function testFuzz_PayoutWithOverridesFailUnauthorized(address _receiver, uint256 _amount, uint _actorIndex) public {
        address _actor = payoutActors[_actorIndex % payoutActors.length];
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_actor);
        _baseToken.approve(address(entity), _amount);
        // set the default payout fee for the entity type to the max to disallow the payout
        vm.prank(board);
        globalTestRegistry.setDefaultPayoutFee(testEntityType, onePercentZoc);
        vm.expectRevert(Unauthorized.selector);
        vm.prank(user1);
        entity.payoutWithOverrides(_receiver, _amount);
    }

    // Test that a payout with fails when the source entity of the transfer has insufficient funds.
    function testFuzz_PayoutWithOverridesFailInsufficientFunds(address _receiver, uint256 _amount, uint _actorIndex) public {
        address _actor = payoutActors[_actorIndex % payoutActors.length];
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        // set the default payout fee for the entity type to the max to disallow the payout
        vm.prank(board);
        globalTestRegistry.setDefaultPayoutFee(testEntityType, onePercentZoc);
        vm.expectRevert(InsufficientFunds.selector);
        vm.prank(_actor);
        entity.payoutWithOverrides(_receiver, _amount);
    }

    // Test a valid transfer between 2 entities
    function testFuzz_TransferSuccess(address _manager, uint256 _amount, uint256 _feePercent, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
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
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
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
        _amount = bound(_amount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
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

    // Test that a transfer fails to an inactive Entity
    function testFuzz_TransferFailInactiveDestination(address _manager, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        vm.startPrank(board);
        entity.setManager(_manager);
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, onePercentZoc);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, false);
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
        _balanceAmount = bound(_balanceAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
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
        _balanceAmount = bound(_balanceAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
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
        _balanceAmount = bound(_balanceAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
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

    // Test that the reconcileBalance function emits an appropriate event when the contract balance is more than the token balance, and is corrected.
    function testFuzz_ReconcileBalanceSuccessWithCorrection(address _manager, uint256 _balanceAmount, uint256 _overageAmount) public {
        _balanceAmount = bound(_balanceAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _overageAmount = bound(_overageAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);

        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _balanceAmount);
        // update the contract balance to be more than the entity balance so the correction can be attempted
        _setEntityContractBalance(entity, _balanceAmount + _overageAmount);
        vm.expectEmit(true, false, false, true);
        emit EntityBalanceCorrected(address(entity), _balanceAmount);
        entity.reconcileBalance();
        assertEq(entity.balance(), _balanceAmount);
    }

    // Test that the reconcileBalance function fails when the entity donations disallowed via default donation fee setting.
    function testFuzz_ReconcileBalanceFailInvalidAction(address _manager, uint256 _balanceAmount, uint256 _sweepAmount) public {
        _balanceAmount = bound(_balanceAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
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

    function testFuzz_SwapAndDonateSuccess(
        address _donor,
        uint256 _donationAmount,
        uint256 _amountOut,
        uint256 _feePercent,
        bool _isActive
    ) public {
        vm.assume(
            _donor != treasury &&
            _donor != address(entity)
        );

        _donationAmount = bound(_donationAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _amountOut = bound(_amountOut, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC); //pick default donation fee percentage between 0 and 100
        mockSwapWrapper.setAmountOut(_amountOut);

        // Set up the entity.
        vm.startPrank(board);
        globalTestRegistry.setEntityStatus(entity, _isActive);
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        vm.stopPrank();

        // Mint and approve test tokens to donor.
        testToken1.mint(_donor, _donationAmount);
        vm.prank(_donor);
        testToken1.approve(address(entity), _donationAmount);

        // Calculate expected results.
        uint256 _expectedFee = Math.zocmul(mockSwapWrapper.amountOut(), _feePercent);
        uint256 _expectedReceived = mockSwapWrapper.amountOut() - _expectedFee;

        // Perform swap and donate.
        vm.expectEmit(true, true, true, true);
        emit EntityDonationReceived(_donor, address(entity), mockSwapWrapper.amountOut(), _expectedFee);
        vm.prank(_donor);
        entity.swapAndDonate(mockSwapWrapper, address(testToken1), _donationAmount, "");

        assertEq(baseToken.balanceOf(address(entity)), _expectedReceived);
        assertEq(entity.balance(), _expectedReceived);
        assertEq(baseToken.balanceOf(treasury), _expectedFee);
    }

    function testFuzz_SwapAndDonateEthSuccess(
        address _donor,
        uint256 _donationAmount,
        uint256 _amountOut,
        uint256 _feePercent,
        bool _isActive
    ) public {
        vm.assume(
            _donor != treasury &&
            _donor != address(entity)
        );

        _donationAmount = bound(_donationAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _amountOut = bound(_amountOut, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC); //pick default donation fee percentage between 0 and 100
        mockSwapWrapper.setAmountOut(_amountOut);

        // Set up the entity.
        vm.startPrank(board);
        globalTestRegistry.setEntityStatus(entity, _isActive);
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        vm.stopPrank();

        // Give ETH to the donor
        vm.deal(_donor, _donationAmount);

        // Calculate expected results.
        uint256 _expectedFee = Math.zocmul(mockSwapWrapper.amountOut(), _feePercent);
        uint256 _expectedReceived = mockSwapWrapper.amountOut() - _expectedFee;

        // Perform swap and donate.
        vm.expectEmit(false, true, true, true); // TODO: WHY IS THIS FAILING IF I MAKE IT TRUE?
        emit EntityDonationReceived(_donor, address(entity), mockSwapWrapper.amountOut(), _expectedFee);
        vm.prank(_donor);
        entity.swapAndDonate{value: _donationAmount}(
            mockSwapWrapper,
            entity.ETH_PLACEHOLDER(),
            _donationAmount,
            ""
        );

        assertEq(baseToken.balanceOf(address(entity)), _expectedReceived);
        assertEq(entity.balance(), _expectedReceived);
        assertEq(baseToken.balanceOf(treasury), _expectedFee);
    }

    function testFuzz_SwapAndDonateFailsIfSwapperIsNotApproved(
        address _donor,
        uint256 _donationAmount,
        uint256 _amountOut,
        uint256 _feePercent,
        bool _isActive
    ) public {
        vm.assume(
            _donor != treasury &&
            _donor != address(entity)
        );

        _donationAmount = bound(_donationAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _amountOut = bound(_amountOut, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC); //pick default donation fee percentage between 0 and 100
        mockSwapWrapper.setAmountOut(_amountOut);

        vm.startPrank(board);
        // Set up the entity.
        globalTestRegistry.setEntityStatus(entity, _isActive);
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        // Un-approve the Swapper.
        globalTestRegistry.setSwapWrapperStatus(mockSwapWrapper, false);
        vm.stopPrank();

        // Mint and approve test tokens to donor.
        testToken1.mint(_donor, _donationAmount);
        vm.prank(_donor);
        testToken1.approve(address(entity), _donationAmount);

        // Attempt to perform swap and donate.
        vm.expectRevert(InvalidAction.selector);
        vm.prank(_donor);
        entity.swapAndDonate(mockSwapWrapper, address(testToken1), _donationAmount, "");
    }

    function testFuzz_SwapAndDonateWithOverridesSuccess(
        address _donor,
        uint256 _donationAmount,
        uint256 _amountOut,
        uint256 _feePercent,
        bool _isActive
    ) public {
        vm.assume(
            _donor != treasury &&
            _donor != address(entity)
        );

        _donationAmount = bound(_donationAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _amountOut = bound(_amountOut, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, onePercentZoc, Math.ZOC); //pick default donation fee percentage between 1 and 100
        mockSwapWrapper.setAmountOut(_amountOut);

        vm.startPrank(board);
        // Set up the entity.
        globalTestRegistry.setEntityStatus(entity, _isActive);
        // Set the default fee.
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        // Set the override fee to 1% lower.
        globalTestRegistry.setDonationFeeReceiverOverride(entity, uint32(_feePercent - onePercentZoc));
        vm.stopPrank();

        // Mint and approve test tokens to donor.
        testToken1.mint(_donor, _donationAmount);
        vm.prank(_donor);
        testToken1.approve(address(entity), _donationAmount);

        // Calculate expected results.
        uint256 _expectedFee = Math.zocmul(mockSwapWrapper.amountOut(), _feePercent - onePercentZoc);
        uint256 _expectedReceived = mockSwapWrapper.amountOut() - _expectedFee;

        // Perform swap and donate.
        vm.expectEmit(true, true, true, true);
        emit EntityDonationReceived(_donor, address(entity), mockSwapWrapper.amountOut(), _expectedFee);
        vm.prank(_donor);
        entity.swapAndDonateWithOverrides(mockSwapWrapper, address(testToken1), _donationAmount, "");

        assertEq(baseToken.balanceOf(address(entity)), _expectedReceived);
        assertEq(entity.balance(), _expectedReceived);
        assertEq(baseToken.balanceOf(treasury), _expectedFee);
    }

    function testFuzz_SwapAndDonateWithOverridesEthSuccess(
        address _donor,
        uint256 _donationAmount,
        uint256 _amountOut,
        uint256 _feePercent,
        bool _isActive
    ) public {
        vm.assume(
            _donor != treasury &&
            _donor != address(entity)
        );

        _donationAmount = bound(_donationAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _amountOut = bound(_amountOut, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, onePercentZoc, Math.ZOC); //pick default donation fee percentage between 1 and 100
        mockSwapWrapper.setAmountOut(_amountOut);

        vm.startPrank(board);
        // Set up the entity.
        globalTestRegistry.setEntityStatus(entity, _isActive);
        // Set the default fee.
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        // Set the override fee to 1% lower.
        globalTestRegistry.setDonationFeeReceiverOverride(entity, uint32(_feePercent - onePercentZoc));
        vm.stopPrank();

        // Give ETH to the donor
        vm.deal(_donor, _donationAmount);

        // Calculate expected results.
        uint256 _expectedFee = Math.zocmul(mockSwapWrapper.amountOut(), _feePercent - onePercentZoc);
        uint256 _expectedReceived = mockSwapWrapper.amountOut() - _expectedFee;

        // Perform swap and donate.
        vm.expectEmit(true, true, true, true);
        emit EntityDonationReceived(_donor, address(entity), mockSwapWrapper.amountOut(), _expectedFee);
        vm.prank(_donor);
        entity.swapAndDonateWithOverrides{value: _donationAmount}(
            mockSwapWrapper,
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // ETH Placeholder.
            _donationAmount,
            ""
        );

        assertEq(baseToken.balanceOf(address(entity)), _expectedReceived);
        assertEq(entity.balance(), _expectedReceived);
        assertEq(baseToken.balanceOf(treasury), _expectedFee);
    }

    function testFuzz_SwapAndReconcileBalanceSuccess(
        address _manager,
        uint256 _balanceAmount,
        uint256 _sweepAmount,
        uint256 _feePercent
    ) public {
        _balanceAmount = bound(_balanceAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC);

        vm.startPrank(board);
        // Set the default donation fee to some percentage between 0 and 100 percent.
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        entity.setManager(_manager);
        vm.stopPrank();

        // Give the Entity a base token balance.
        _setEntityBalance(entity, _balanceAmount);
        // Mint some test tokens directly to the entity.
        testToken1.mint(address(entity), _sweepAmount);

         // Calculate expected results.
        uint256 _expectedFee = Math.zocmul(mockSwapWrapper.amountOut(), _feePercent);
        uint256 _expectedReceived = mockSwapWrapper.amountOut() - _expectedFee;

        vm.expectEmit(true, true, true, true);
        emit EntityBalanceReconciled(address(entity), mockSwapWrapper.amountOut(), _expectedFee);
        vm.prank(_manager);
        entity.swapAndReconcileBalance(mockSwapWrapper, address(testToken1), _sweepAmount, "");

        assertEq(baseToken.balanceOf(treasury), _expectedFee);
        assertEq(entity.balance(), _balanceAmount + _expectedReceived);
    }

    function testFuzz_SwapAndReconcileBalanceOverrideFeeSuccess(
        address _manager,
        uint256 _balanceAmount,
        uint256 _sweepAmount,
        uint256 _feePercent
    ) public {
        _balanceAmount = bound(_balanceAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, onePercentZoc, Math.ZOC);

        vm.startPrank(board);
        entity.setManager(_manager);
        // Set the default fee.
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        // Set the override fee to 1% lower.
        globalTestRegistry.setDonationFeeReceiverOverride(entity, uint32(_feePercent - onePercentZoc));
        vm.stopPrank();

        // Give the Entity a base token balance.
        _setEntityBalance(entity, _balanceAmount);
        // Mint some test tokens directly to the entity.
        testToken1.mint(address(entity), _sweepAmount);

         // Calculate expected results.
        uint256 _expectedFee = Math.zocmul(mockSwapWrapper.amountOut(), _feePercent - onePercentZoc);
        uint256 _expectedReceived = mockSwapWrapper.amountOut() - _expectedFee;

        vm.expectEmit(true, true, true, true);
        emit EntityBalanceReconciled(address(entity), mockSwapWrapper.amountOut(), _expectedFee);
        vm.prank(_manager);
        entity.swapAndReconcileBalance(mockSwapWrapper, address(testToken1), _sweepAmount, "");

        assertEq(baseToken.balanceOf(treasury), _expectedFee);
        assertEq(entity.balance(), _balanceAmount + _expectedReceived);
    }

    function testFuzz_SwapAndReconcileBalanceEthSuccess(
        address _manager,
        uint256 _balanceAmount,
        uint256 _sweepAmount,
        uint256 _feePercent
    ) public {
        _balanceAmount = bound(_balanceAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC);

        vm.startPrank(board);
        // Set the default donation fee to some percentage between 0 and 100 percent.
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        entity.setManager(_manager);
        vm.stopPrank();

        // Give the Entity a base token balance.
        _setEntityBalance(entity, _balanceAmount);
        // Send ETH directly to the entity.
        vm.deal(address(entity), _sweepAmount);

         // Calculate expected results.
        uint256 _expectedFee = Math.zocmul(mockSwapWrapper.amountOut(), _feePercent);
        uint256 _expectedReceived = mockSwapWrapper.amountOut() - _expectedFee;

        vm.expectEmit(true, true, true, true);
        emit EntityBalanceReconciled(address(entity), mockSwapWrapper.amountOut(), _expectedFee);
        vm.prank(_manager);
        entity.swapAndReconcileBalance(
            mockSwapWrapper,
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // ETH Placeholder
            _sweepAmount,
            ""
        );

        assertEq(baseToken.balanceOf(treasury), _expectedFee);
        assertEq(entity.balance(), _balanceAmount + _expectedReceived);
    }

    function testFuzz_SwapAndReconcileBalanceFailsIfSwapperIsNotApproved(
        address _manager,
        uint256 _balanceAmount,
        uint256 _sweepAmount,
        uint256 _feePercent
    ) public {
        _balanceAmount = bound(_balanceAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _sweepAmount = bound(_sweepAmount, MIN_ENTITY_TRANSACTION_AMOUNT, MAX_ENTITY_TRANSACTION_AMOUNT);
        _feePercent = bound(_feePercent, 0, Math.ZOC);

        vm.startPrank(board);
        // Set the default donation fee to some percentage between 0 and 100 percent.
        globalTestRegistry.setDefaultDonationFee(testEntityType, uint32(_feePercent));
        entity.setManager(_manager);
        // Un-approve the mock swapper.
        globalTestRegistry.setSwapWrapperStatus(mockSwapWrapper, false);
        vm.stopPrank();

        // Give the Entity a base token balance.
        _setEntityBalance(entity, _balanceAmount);
        // Mint some test tokens directly to the entity.
        testToken1.mint(address(entity), _sweepAmount);

        vm.expectRevert(InvalidAction.selector);
        vm.prank(_manager);
        entity.swapAndReconcileBalance(mockSwapWrapper, address(testToken1), _sweepAmount, "");
    }
}

contract OrgTokenTransactionTest is EntityTokenTransactionTest {
    // this will run all tests in EntityTokenTransactionTest
    function setUp() public override {
        super.setUp();
        entity = orgFundFactory.deployOrg("someOrgId", "someSalt");
        testEntityType = OrgType;
    }
}

contract FundTokenTransactionTest is EntityTokenTransactionTest {
    // this will run all tests in EntityTokenTransactionTest
    function setUp() public override {
        super.setUp();
        entity = orgFundFactory.deployFund(address(0x1111), "someSalt");
        testEntityType = FundType;
    }
}

contract CallAsEntityTest is EntityHarness {

    error CallFailed(bytes response);

    error AlwaysReverts();

    function alwaysRevertsCustom() external pure {
        revert AlwaysReverts();
    }

    function alwaysRevertsString() external pure {
        revert("ALWAYS_REVERT");
    }

    function alwaysRevertsSilently() external pure {
        revert();
    }

    function testFuzz_CanCallAsEntity(uint8 _entityType, address _manager, address _receiver, uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint256).max);
        uint256 _initialBalance = baseToken.balanceOf(_receiver);

        // Deploy an entity and give it tokens directly
        _deployEntity(_entityType, _manager);
        baseToken.mint(address(receivingEntity), _amount);

        // Transfer tokens out via callAsEntity method
        bytes memory _data = abi.encodeCall(baseToken.transfer, (_receiver, _amount));
        vm.prank(board);
        bytes memory _returnData = receivingEntity.callAsEntity(address(baseToken), 0, _data);
        (bool _transferSuccess) = abi.decode(_returnData, (bool));

        assertTrue(_transferSuccess);
        assertEq(baseToken.balanceOf(_receiver) - _initialBalance, _amount);
    }

    function testFuzz_CallAsEntityForwardsRevertString(
        uint8 _entityType,
        address _manager
    ) public {
        _deployEntity(_entityType, _manager);

        // Bytes precalculated for this revert string.
        bytes memory _expectedRevert = abi.encodeWithSelector(
            CallFailed.selector,
            hex"08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000"
            hex"000000000000000000000000000000000d414c574159535f52455645525400000000000000000000000000000000000000"
        );

        // Call a method that reverts and verify the data is forwarded.
        bytes memory _data = abi.encodeCall(this.alwaysRevertsString, ());
        vm.prank(board);
        vm.expectRevert(_expectedRevert);
        receivingEntity.callAsEntity(address(this), 0, _data);
    }

    function testFuzz_CallAsEntityForwardsCustomError(
        uint8 _entityType,
        address _manager
    ) public {
        _deployEntity(_entityType, _manager);

        // Bytes precalculated for this custom error.
        bytes memory _expectedRevert = abi.encodeWithSelector(CallFailed.selector, hex"47e794ec");

        // Call a method that reverts and verify the data is forwarded.
        bytes memory _data = abi.encodeCall(this.alwaysRevertsCustom, ());
        vm.prank(board);
        vm.expectRevert(_expectedRevert);
        receivingEntity.callAsEntity(address(this), 0, _data);
    }

    function testFuzz_CallAsEntityForwardsSilentRevert(
        uint8 _entityType,
        address _manager
    ) public {
        _deployEntity(_entityType, _manager);

        // A silent error has no additional bytes.
        bytes memory _expectedRevert = abi.encodeWithSelector(CallFailed.selector, "");

        // Call a method that reverts and no data is forwarded.
        bytes memory _data = abi.encodeCall(this.alwaysRevertsSilently, ());
        vm.prank(board);
        vm.expectRevert(_expectedRevert);
        receivingEntity.callAsEntity(address(this), 0, _data);
    }

    function testFuzz_ManagerCannotCallAsEntity(
        uint8 _entityType,
        address _manager,
        address _receiver,
        uint256 _amount
    ) public {
        _amount = bound(_amount, 1, type(uint256).max - 1);
        vm.assume(_manager != board);

        // Deploy an entity and give it tokens directly
        _deployEntity(_entityType, _manager);
        baseToken.mint(address(receivingEntity), _amount);

        // Attempt to transfer tokens out via callAsEntity method as the manager
        bytes memory _data = abi.encodeCall(baseToken.transfer, (_receiver, _amount));
        vm.prank(_manager);
        vm.expectRevert(Unauthorized.selector);
        receivingEntity.callAsEntity(address(baseToken), 0, _data);
    }

    function testFuzz_CanCallAsEntityToSendETH(
        uint8 _entityType,
        address _manager,
        address _receiver,
        uint256 _amount
    ) public {
        _deployEntity(_entityType, _manager);

        // Ensure the fuzzer hasn't picked one of our contracts, which won't have a fallback.
        vm.assume(address(_receiver).code.length == 0);
        uint256 _initialBalance = _receiver.balance;

        // Give the entity an ETH balance.
        vm.deal(address(receivingEntity), _amount);

        // Use callAsEntity to send ETH to receiver.
        vm.prank(board);
        receivingEntity.callAsEntity(_receiver, _amount, "");

        assertEq(address(_receiver).balance - _initialBalance, _amount);
    }

    function testFuzz_CanCallAsEntityToForwardETH(
        uint8 _entityType,
        address _manager,
        address _receiver,
        uint256 _amount
    ) public {
        _deployEntity(_entityType, _manager);

        // Ensure the fuzzer hasn't picked one of our contracts, which won't have a fallback.
        vm.assume(address(_receiver).code.length == 0);

        uint256 _initialBalance = _receiver.balance;

        // Give the entity an ETH balance.
        vm.deal(board, _amount);

        // Use callAsEntity to send ETH to receiver.
        vm.prank(board);
        receivingEntity.callAsEntity{value: _amount}(_receiver, _amount, "");

        assertEq(address(_receiver).balance - _initialBalance, _amount);
    }
}
