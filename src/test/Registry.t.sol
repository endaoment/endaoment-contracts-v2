// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import { Registry } from "../Registry.sol";
import { OrgFundFactory } from "../OrgFundFactory.sol";
import { Org } from "../Org.sol";
import { Fund } from "../Fund.sol";
import { Entity } from "../Entity.sol";

contract RegistryTest is DeployTest {
    event FactoryApprovalSet(address indexed factory, bool isApproved);
    event EntityStatusSet(address indexed entity, bool isActive);
    event DefaultDonationFeeSet(uint8 indexed entityType, uint32 fee);
    event DonationFeeReceiverOverrideSet(address indexed entity, uint32 fee);
    event DefaultTransferFeeSet(uint8 indexed fromEntitytype, uint8 indexed toEntityType, uint32 fee);
    event TransferFeeSenderOverrideSet(address indexed fromEntity, uint8 indexed toEntityType, uint32 fee);
    event TransferFeeReceiverOverrideSet(uint8 indexed fromEntityType, address indexed toEntity, uint32 fee);
}

contract RegistryConstructor is RegistryTest {

    function testFuzz_RegistryConstructor(address _admin, address _treasury, address _baseToken) public {
        Registry _registry = new Registry(_admin, _treasury, ERC20(_baseToken));
        assertEq(_registry.owner(), _admin);
        assertEq(_registry.treasury(), _treasury);
        assertEq(address(_registry.baseToken()), _baseToken);
    }
}

contract RegistrySetFactoryApproval is RegistryTest {

    function testFuzz_SetFactoryApprovalTrue(address _factoryAddress) public {
        vm.expectEmit(true, false, false, false);
        emit FactoryApprovalSet(_factoryAddress, true);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(_factoryAddress), true);
        assertTrue(globalTestRegistry.isApprovedFactory(_factoryAddress));
    }

    function testFuzz_SetFactoryApprovalFalse(address _factoryAddress) public {
        vm.expectEmit(true, false, false, false);
        emit FactoryApprovalSet(_factoryAddress, false);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(_factoryAddress, false);
        assertFalse(globalTestRegistry.isApprovedFactory(_factoryAddress));
    }

    function testFuzz_SetFactoryApprovalUnauthorized(address _factoryAddress) public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        globalTestRegistry.setFactoryApproval(_factoryAddress, true);
    }
}

contract RegistrySetEntityActive is RegistryTest {
    function testFuzz_SetEntityActive(address _factory, Entity _entity) public {       
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(_factory, true);
        vm.expectEmit(true, false, false, false);
        emit EntityStatusSet(address(_entity), true);
        vm.prank(_factory);
        globalTestRegistry.setEntityActive(_entity);
        assertEq(globalTestRegistry.isActiveEntity(_entity), true);
    }

    function testFuzz_SetEntityActiveFail(address _badFactory, Entity _entity) public {       
        vm.expectRevert(Unauthorized.selector);
        vm.prank(_badFactory);
        globalTestRegistry.setEntityActive(_entity);
    }
}

contract RegistrySetEntityStatus is RegistryTest {
    address[] public actors = [board, capitalCommittee];
    function testFuzz_SetEntityStatus(Entity _entity, bool _status, uint _actor) public {
        address actor = actors[_actor % actors.length];
        vm.expectEmit(true, false, false, false);
        emit EntityStatusSet(address(_entity), _status);
        vm.prank(actor);
        globalTestRegistry.setEntityStatus(_entity, _status);
        assertEq(globalTestRegistry.isActiveEntity(_entity), _status);
    }

    function testFuzz_SetEntityStatusUnauthorized(Entity _entity, bool _status) public {
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setEntityStatus(_entity, _status);
    }
}

// Tests to verify that permissioned addresses can set the default donation fee for entity types.
// The 0 <--> max fee "flip" logic in the `Registry` contract `_parseFee` function means that "unmapped" fees
// would return max and ultimately cause donation calculation reverts.
// These tests verify the correct functioning of the "flip" logic.
contract RegistrySetDefaultDonationFee is RegistryTest {
    address[] public actors = [board, programCommittee];

    // test to set fee for an entity type
    function testFuzz_SetDefaultDonationFee(uint32 _fee, uint _actor, address _manager) public {
        vm.assume( (_fee > 0) && (_fee < type(uint32).max) );
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.expectEmit(true, false, false, false);
        emit DefaultDonationFeeSet(FundType, _fee);
        vm.prank(actor);
        globalTestRegistry.setDefaultDonationFee(FundType, _fee);
        assertEq(globalTestRegistry.getDonationFee(_fund), _fee);
    }

    // Test that an unmapped default fee causes the return of max value
    function testFuzz_UnmappedDefaultDonationFee(address _manager) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        assertEq(globalTestRegistry.getDonationFee(_fund), type(uint32).max);
    }

    // Test zeroing the fee.
    function testFuzz_SetDefaultDonationFeeToNoFee(uint _actor, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.expectEmit(true, false, false, false);
        emit DefaultDonationFeeSet(OrgType, 0);
        vm.prank(actor);
        globalTestRegistry.setDefaultDonationFee(OrgType, 0);
        assertEq(globalTestRegistry.getDonationFee(_org), 0);
    }

    // test maxing fee via setting value to maxint 
    function testFuzz_SetDefaultDonationFeeToMax(uint _actor, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.expectEmit(true, false, false, false);
        emit DefaultDonationFeeSet(OrgType, type(uint32).max);
        vm.prank(actor);
        globalTestRegistry.setDefaultDonationFee(OrgType, type(uint32).max);
        assertEq(globalTestRegistry.getDonationFee(_org), type(uint32).max);
    }

    // Test that an unauthorized user  cannot set the fee.
    function testFuzz_SetDefaultDonationFeeUnauthorized(uint8 _entityType, uint32 _fee) public {
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setDefaultDonationFee(_entityType, _fee);
    }
}

// Tests to verify that permissioned addresses can set the donation fee override for specific entities.
// This is accomplished by setting the default donation fee for an entity type, then setting an override for a specific entity
// then verifying that the specific entity got the override correctly set and another entity correctly had the default fee.
// These tests also verify the fee "flip" logic.
contract RegistrySetDonationFeeReceiverOverride is RegistryTest {
    address[] public actors = [board, programCommittee];

    // test that fee override for a specific receiving entity causes the fetch of the overridden fee
    function testFuzz_SetDonationFeeReceiverOverride(uint32 _fee, uint _actor, address _manager1, address _manager2) public {
        vm.assume(_manager1 != _manager2);
        vm.assume( (_fee > 0) && (_fee < (type(uint32).max-1)) );
        address actor = actors[_actor % actors.length];
        Fund _fund1 = orgFundFactory.deployFund(_manager1, "salt");
        Fund _fund2 = orgFundFactory.deployFund(_manager2, "salt");
        vm.startPrank(actor);
        vm.expectEmit(true, false, false, false);
        emit DefaultDonationFeeSet(FundType, _fee + 1);
        globalTestRegistry.setDefaultDonationFee(FundType, _fee + 1);
        vm.expectEmit(true, false, false, false);
        emit DonationFeeReceiverOverrideSet(address(_fund1), _fee);
        globalTestRegistry.setDonationFeeReceiverOverride(_fund1, _fee);
        vm.stopPrank();
        assertEq(globalTestRegistry.getDonationFee(_fund1), _fee);
        assertEq(globalTestRegistry.getDonationFee(_fund2), _fee + 1);
    }

    // test zeroing the override for a specific receiving entity triggers an override of no fee
    function testFuzz_SetDonationFeeReceiverOverrideToNoFee(uint _actor, bytes32 _orgId1, bytes32 _orgId2) public {
        vm.assume(_orgId1 != _orgId2);
        address actor = actors[_actor % actors.length];
        Org _org1 = orgFundFactory.deployOrg(_orgId1, "salt");
        Org _org2 = orgFundFactory.deployOrg(_orgId2, "salt");
        vm.startPrank(actor);
        vm.expectEmit(true, false, false, false);
        emit DefaultDonationFeeSet(OrgType, 10);
        globalTestRegistry.setDefaultDonationFee(OrgType, 10);
        vm.expectEmit(true, false, false, false);
        emit DonationFeeReceiverOverrideSet(address(_org1), 0);
        globalTestRegistry.setDonationFeeReceiverOverride(_org1, 0);
        vm.stopPrank();
        assertEq(globalTestRegistry.getDonationFee(_org1), 0);
        assertEq(globalTestRegistry.getDonationFee(_org2), 10);
    }

    // test that an unauthorized user  cannot set the fee override
    function testFuzz_SetDonationFeeReceiverOverrideUnauthorized(address _manager, uint32 _fee) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setDonationFeeReceiverOverride(_fund, _fee);
    }
}

// Tests to verify that permissioned addresses can set the default transfer fee between 2 entity types.
// The 0 <--> max fee "flip" logic in the `Registry` contract `_parseFee` function means that "unmapped" fees
// would return max and ultimately cause transfer fee calculation reverts.
// Setting the fee to 0 implies setting it to `type(uint32).max`.
// These tests verify the correct functioning of the "flip" logic.
contract RegistrySetDefaultTransferFee is RegistryTest {
    address[] public actors = [board, programCommittee];

    // test the setting of default transfer fee between 2 entity types
    function testFuzz_SetDefaultTransferFee(uint32 _fee, uint _actor, address _manager, bytes32 _orgId) public {
        vm.assume( (_fee > 0) && (_fee < (type(uint32).max)) );
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, _fee);
        vm.prank(actor);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, _fee);
        assertEq(globalTestRegistry.getTransferFee(_fund, _org), _fee);
    }

    // Test that an unmapped default fee causes the return of max value
    function testFuzz_UnmappedDefaultTransferFee(address _manager, bytes32 _orgId) public {
        Org org = orgFundFactory.deployOrg(_orgId, "salt");
        Fund fund = orgFundFactory.deployFund(_manager, "salt");
        assertEq(globalTestRegistry.getTransferFee(fund, org), type(uint32).max);
    }

    // test zeroing the default transfer fee between 2 entity types
    function testFuzz_SetDefaultTransferFeeNoFee(uint _actor, address _manager, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, 0);
        vm.prank(actor);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, 0);
        assertEq(globalTestRegistry.getTransferFee(_fund, _org), 0);
    }

    // test maxing the default transfer fee between 2 entity types
    function testFuzz_SetDefaultTransferFeeToMax(uint _actor, address _manager, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, type(uint32).max);
        vm.prank(actor);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, type(uint32).max);
        assertEq(globalTestRegistry.getTransferFee(_fund, _org), type(uint32).max);
    }

    // test that an unauthorized user  cannot set the default transfer fee between 2 entity types
    function testFuzz_SetDefaultTransferFeeUnauthorized(uint32 _fee) public {
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, _fee);
    }
}

// Tests to verify that permissioned addresses can set the transfer fee sender override for specific entities.
// This is accomplished by setting the default transfer fee between 2 entity types, then setting an override for a specific entity
// then verifying that the specific entity got the override correctly set and another entity correctly had the default fee.
// These tests also verify the fee "flip" logic.
contract RegistrySetTransferFeeSenderOverride is RegistryTest {
    address[] public actors = [board, programCommittee];

    // test the setting of the transfer fee sender override for an entity
    function testFuzz_SetTransferFeeSenderOverride(uint32 _fee, uint _actor, address _manager1, address _manager2, bytes32 _orgId) public {
        vm.assume(_manager1 != _manager2);
        vm.assume( (_fee > 0) && (_fee < (type(uint32).max-1)) );
        address actor = actors[_actor % actors.length];
        Fund _fund1 = orgFundFactory.deployFund(_manager1, "salt");
        Fund _fund2 = orgFundFactory.deployFund(_manager2, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.startPrank(actor);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, _fee + 1);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, _fee + 1);
        vm.expectEmit(true, true, false, false);
        emit TransferFeeSenderOverrideSet(address(_fund1), OrgType, _fee);
        globalTestRegistry.setTransferFeeSenderOverride(_fund1, OrgType, _fee);
        vm.stopPrank();
        assertEq(globalTestRegistry.getTransferFee(_fund1, _org), _fee);
        assertEq(globalTestRegistry.getTransferFee(_fund2, _org), _fee + 1);
    }

    // test the setting of the transfer fee sender override for an entity to zero
    function testFuzz_SetTransferFeeSenderOverrideToNoFee(uint _actor, address _manager1, address _manager2, bytes32 _orgId) public {
        vm.assume(_manager1 != _manager2);
        address actor = actors[_actor % actors.length];
        Fund _fund1 = orgFundFactory.deployFund(_manager1, "salt");
        Fund _fund2 = orgFundFactory.deployFund(_manager2, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.startPrank(actor);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, 10);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, 10);
        vm.expectEmit(true, true, false, false);
        emit TransferFeeSenderOverrideSet(address(_fund1), OrgType, 0);
        globalTestRegistry.setTransferFeeSenderOverride(_fund1, OrgType, 0);
        vm.stopPrank();
        assertEq(globalTestRegistry.getTransferFee(_fund1, _org), 0);
        assertEq(globalTestRegistry.getTransferFee(_fund2, _org), 10);
    }

    // test that an unauthorized user  cannot set the transfer fee sender override
    function testFuzz_SetTransferFeeSenderOverrideUnauthorized(uint32 _fee, address _manager) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setTransferFeeSenderOverride(_fund, OrgType, _fee);
    }
}

// Tests to verify that permissioned addresses can set the transfer fee receiver override for specific entities.
// This is accomplished by setting the default transfer fee between 2 entity types, then setting an override for a specific entity
// then verifying that the specific entity got the override correctly set and another entity correctly had the default fee.
// These tests also verify the fee "flip" logic.
contract RegistrySetTransferFeeReceiverOverride is RegistryTest {
    address[] public actors = [board, programCommittee];

    // test the setting of the transfer fee receiver override for an entity
    function testFuzz_SetTransferFeeReceiverOverride(uint32 _fee, uint _actor, address _manager, bytes32 _orgId1, bytes32 _orgId2) public {
        vm.assume(_orgId1 != _orgId2);
        vm.assume( (_fee > 0) && (_fee < (type(uint32).max-1)) );
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org1 = orgFundFactory.deployOrg(_orgId1, "salt");
        Org _org2 = orgFundFactory.deployOrg(_orgId2, "salt");
        vm.startPrank(actor);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, _fee + 1);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, _fee + 1);
        vm.expectEmit(true, true, false, false);
        emit TransferFeeReceiverOverrideSet(FundType, address(_org1), _fee);
        globalTestRegistry.setTransferFeeReceiverOverride(FundType, _org1, _fee);
        vm.stopPrank();
        assertEq(globalTestRegistry.getTransferFee(_fund, _org1), _fee);
        assertEq(globalTestRegistry.getTransferFee(_fund, _org2), _fee + 1);
    }

    // test the setting of the transfer fee receiver override for an entity to zero
    function testFuzz_SetTransferFeeReceiverOverrideToNoFee(uint _actor, address _manager, bytes32 _orgId1, bytes32 _orgId2) public {
        vm.assume(_orgId1 != _orgId2);
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org1 = orgFundFactory.deployOrg(_orgId1, "salt");
        Org _org2 = orgFundFactory.deployOrg(_orgId2, "salt");
        vm.startPrank(actor);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, 10);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, 10);
        vm.expectEmit(true, true, false, false);
        emit TransferFeeReceiverOverrideSet(FundType, address(_org1), 0);
        globalTestRegistry.setTransferFeeReceiverOverride(FundType, _org1, 0);
        vm.stopPrank();
        assertEq(globalTestRegistry.getTransferFee(_fund, _org1), 0);
        assertEq(globalTestRegistry.getTransferFee(_fund, _org2), 10);
    }

    // test that an unauthorized user  cannot set the transfer fee sender override
    function testFuzz_SetTransferFeeReceiverOverrideUnauthorized(uint32 _fee, bytes32 _orgId) public {
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setTransferFeeReceiverOverride(FundType, _org, _fee);
    }
}
