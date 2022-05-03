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

    event EntityDonationReceived(address indexed from, address indexed to, uint256 amount, uint256 fee);
    event EntityFundsTransferred(address indexed from, address indexed to, uint256 amountReceived, uint256 amountFee);

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

    // local helper function to convert a percent value to a zoc value
    function _percentToZoc(uint256 _percentValue) internal returns (uint32) {
        return uint32(_percentValue * Math.ZOC) / 100;
    }

    // Test a normal donation to an entity from a donor.
    function testFuzz_DonateSuccess(address _donor, uint256 _donationAmount, uint256 _feePercent) public {
        _donationAmount = bound(_donationAmount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        vm.assume(_donor != treasury);
        _feePercent = bound(_feePercent, 0, Math.ZOC);
        vm.prank(board);
        // set the default donation fee to some percentage between 1 and 5 percent
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

    // Test a valid transfer between 2 entities
    function testFuzz_TransferSuccess(address _manager, uint256 _amount, uint256 _feePercent, address _receivingManager, uint8 _receivingEntityTypeIndex) public {
        _amount = bound(_amount, MIN_DONATION_TRANSFER_AMOUNT, MAX_DONATION_TRANSFER_AMOUNT);
        _feePercent = bound(_feePercent, 0, 5);
        // get the receiving entity type from the fuzzed parameter
        uint8 _receivingType = _deployEntity(_receivingEntityTypeIndex, _receivingManager);
        // preset the requested amount of basetokens into the entity
        _setEntityBalance(entity, _amount);
        ERC20 _baseToken = globalTestRegistry.baseToken();
        vm.prank(_manager);
        _baseToken.approve(address(entity), _amount);
        // set the default transfer fee between the 2 entity types to some percentage between 1 and 5 percent
        vm.startPrank(board);
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, _percentToZoc(_feePercent));
        entity.setManager(_manager);
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        uint256 _amountFee = Math.zocmul(_amount, _percentToZoc(_feePercent));
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
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, _percentToZoc(1));
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
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, _percentToZoc(1));
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
        globalTestRegistry.setDefaultTransferFee(testEntityType, _receivingType, _percentToZoc(1));
        globalTestRegistry.setEntityStatus(entity, true);
        globalTestRegistry.setEntityStatus(receivingEntity, true);
        vm.stopPrank();
        vm.prank(_manager);
        vm.expectRevert(abi.encodeWithSelector(InsufficientFunds.selector));
        entity.transfer(receivingEntity, 1);
    }

    // Test than the receiveTransfer function fails if not called by another entity.
    // The 'happy path' of receiveTransfer function testing is performed above in testFuzz_TransferSuccess.
    function testFuzz_ReceiveTransferFailInvalidTransferAttempt(uint256 _transferAmount) public {
        vm.expectRevert(InvalidTransferAttempt.selector);
        vm.prank(board);
        entity.receiveTransfer(_transferAmount);
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
