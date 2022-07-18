// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "./utils/DeployTest.sol";
import {Registry} from "../Registry.sol";
import {OrgFundFactory} from "../OrgFundFactory.sol";
import {Org} from "../Org.sol";
import {Fund} from "../Fund.sol";
import {Entity} from "../Entity.sol";
import {ISwapWrapper} from "../interfaces/ISwapWrapper.sol";

contract RegistryTest is DeployTest {
    event FactoryApprovalSet(address indexed factory, bool isApproved);
    event EntityStatusSet(address indexed entity, bool isActive);
    event DefaultDonationFeeSet(uint8 indexed entityType, uint32 fee);
    event DonationFeeReceiverOverrideSet(address indexed entity, uint32 fee);
    event DefaultPayoutFeeSet(uint8 indexed entityType, uint32 fee);
    event PayoutFeeOverrideSet(address indexed entity, uint32 fee);
    event DefaultTransferFeeSet(uint8 indexed fromEntitytype, uint8 indexed toEntityType, uint32 fee);
    event TransferFeeSenderOverrideSet(address indexed fromEntity, uint8 indexed toEntityType, uint32 fee);
    event TransferFeeReceiverOverrideSet(uint8 indexed fromEntityType, address indexed toEntity, uint32 fee);
    event SwapWrapperStatusSet(address indexed swapWrapper, bool isActive);
    event PortfolioStatusSet(address indexed portfolio, bool isActive);
    event TreasuryChanged(address oldTreasury, address indexed newTreasury);
}

contract RegistryConstructor is RegistryTest {
    function testFuzz_RegistryConstructor(address _admin, address _treasury, address _baseToken) public {
        vm.expectEmit(true, false, false, true);
        emit TreasuryChanged(address(0), _treasury);
        Registry _registry = new Registry(_admin, _treasury, ERC20(_baseToken));
        assertEq(_registry.owner(), _admin);
        assertEq(_registry.treasury(), _treasury);
        assertEq(address(_registry.baseToken()), _baseToken);
    }
}

contract RegistrySetTreasury is RegistryTest {
    address[] public actors = [board];

    function testFuzzSetTreasurySuccess(address _newTreasuryAddress, uint256 _actor) public {
        vm.expectEmit(true, false, false, true);
        emit TreasuryChanged(globalTestRegistry.treasury(), _newTreasuryAddress);
        address actor = actors[_actor % actors.length];
        vm.prank(actor);
        globalTestRegistry.setTreasury(_newTreasuryAddress);
        assertEq(_newTreasuryAddress, globalTestRegistry.treasury());
    }

    function testFuzzSetTreasuryFailUnauthorized(address _newTreasuryAddress) public {
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setTreasury(_newTreasuryAddress);
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
        vm.assume(_badFactory != address(orgFundFactory));
        vm.expectRevert(Unauthorized.selector);
        vm.prank(_badFactory);
        globalTestRegistry.setEntityActive(_entity);
    }
}

contract RegistrySetEntityStatus is RegistryTest {
    address[] public actors = [board, capitalCommittee];

    function testFuzz_SetEntityStatus(Entity _entity, bool _status, uint256 _actor) public {
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

contract RegistrySetSwapWrapperStatus is RegistryTest {
    function testFuzz_SetSwapWrapperStatus(ISwapWrapper _swapWrapper, bool _status) public {
        vm.expectEmit(true, true, false, false);
        emit SwapWrapperStatusSet(address(_swapWrapper), _status);
        vm.prank(board);
        globalTestRegistry.setSwapWrapperStatus(_swapWrapper, _status);
        assertEq(globalTestRegistry.isSwapperSupported(_swapWrapper), _status);
    }

    function testFuzz_SetSwapWrapperStatusUnauthorized(ISwapWrapper _swapWrapper, bool _status) public {
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setSwapWrapperStatus(_swapWrapper, _status);
    }
}

contract RegistrySetPortfolioStatus is RegistryTest {
    address[] actors = [board, investmentCommittee];

    function testFuzz_SetPortfolioStatus(Portfolio _portfolio, bool _status, uint256 _actor) public {
        address actor = actors[_actor % actors.length];
        vm.expectEmit(true, true, false, false);
        emit PortfolioStatusSet(address(_portfolio), _status);
        vm.prank(actor);
        globalTestRegistry.setPortfolioStatus(_portfolio, _status);
        assertEq(globalTestRegistry.isActivePortfolio(_portfolio), _status);
    }

    function testFuzz_SetPortfolioStatusFailUnauthorized(Portfolio _portfolio, bool _status) public {
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setPortfolioStatus(_portfolio, _status);
    }
}

// Tests to verify that permissioned addresses can set the default donation fee for entity types.
// The 0 <--> max fee "flip" logic in the `Registry` contract `_parseFee` function means that "unmapped" fees
// would return max and ultimately cause donation calculation reverts.
// These tests verify the correct functioning of the "flip" logic.
contract RegistrySetDefaultDonationFee is RegistryTest {
    address[] public actors = [board, programCommittee];

    // test to set fee for an entity type
    function testFuzz_SetDefaultDonationFee(uint32 _fee, uint256 _actor, address _manager) public {
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
    function testFuzz_SetDefaultDonationFeeToNoFee(uint256 _actor, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.expectEmit(true, false, false, false);
        emit DefaultDonationFeeSet(OrgType, 0);
        vm.prank(actor);
        globalTestRegistry.setDefaultDonationFee(OrgType, 0);
        assertEq(globalTestRegistry.getDonationFee(_org), 0);
    }

    // test maxing fee via setting value to maxint
    function testFuzz_SetDefaultDonationFeeToMax(uint256 _actor, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Org _org = orgFundFactory.deployOrg(_orgId);
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
    function testFuzz_SetDonationFeeReceiverOverride(uint32 _fee, uint256 _actor, address _manager1, address _manager2)
        public
    {
        vm.assume(_manager1 != _manager2);
        vm.assume((_fee > 0) && (_fee < (type(uint32).max - 1)));
        address actor = actors[_actor % actors.length];
        Fund _fund1 = orgFundFactory.deployFund(_manager1, "salt");
        Fund _fund2 = orgFundFactory.deployFund(_manager2, "salt2");
        vm.startPrank(actor);
        vm.expectEmit(true, false, false, false);
        emit DefaultDonationFeeSet(FundType, _fee + 1);
        globalTestRegistry.setDefaultDonationFee(FundType, _fee + 1);
        vm.expectEmit(true, false, false, false);
        emit DonationFeeReceiverOverrideSet(address(_fund1), _fee);
        globalTestRegistry.setDonationFeeReceiverOverride(_fund1, _fee);
        vm.stopPrank();
        assertEq(globalTestRegistry.getDonationFeeWithOverrides(_fund1), _fee);
        assertEq(globalTestRegistry.getDonationFeeWithOverrides(_fund2), _fee + 1);
    }

    // test zeroing the override for a specific receiving entity triggers an override of no fee
    function testFuzz_SetDonationFeeReceiverOverrideToNoFee(uint256 _actor, bytes32 _orgId1, bytes32 _orgId2) public {
        vm.assume(_orgId1 != _orgId2);
        address actor = actors[_actor % actors.length];
        Org _org1 = orgFundFactory.deployOrg(_orgId1);
        Org _org2 = orgFundFactory.deployOrg(_orgId2);
        vm.startPrank(actor);
        vm.expectEmit(true, false, false, false);
        emit DefaultDonationFeeSet(OrgType, 10);
        globalTestRegistry.setDefaultDonationFee(OrgType, 10);
        vm.expectEmit(true, false, false, false);
        emit DonationFeeReceiverOverrideSet(address(_org1), 0);
        globalTestRegistry.setDonationFeeReceiverOverride(_org1, 0);
        vm.stopPrank();
        assertEq(globalTestRegistry.getDonationFeeWithOverrides(_org1), 0);
        assertEq(globalTestRegistry.getDonationFeeWithOverrides(_org2), 10);
    }

    // test that not setting the override for a specific receiving entity causes getDonationFeeWithOverrides to return the default fee
    function testFuzz_SetDonationFeeReceiverOverrideNotDoneYieldsDefaultFee(uint256 _actor, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.startPrank(actor);
        vm.expectEmit(true, false, false, false);
        emit DefaultDonationFeeSet(OrgType, 10);
        globalTestRegistry.setDefaultDonationFee(OrgType, 10);
        vm.stopPrank();
        assertEq(globalTestRegistry.getDonationFeeWithOverrides(_org), 10);
    }

    // test that an unauthorized user  cannot set the fee override
    function testFuzz_SetDonationFeeReceiverOverrideUnauthorized(address _manager, uint32 _fee) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setDonationFeeReceiverOverride(_fund, _fee);
    }
}

// Tests to verify that permissioned addresses can set the default payout fee for entity types.
// The 0 <--> max fee "flip" logic in the `Registry` contract `_parseFee` function means that "unmapped" fees
// would return max and ultimately cause payout calculation reverts.
// These tests verify the correct functioning of the "flip" logic.
contract RegistrySetDefaultPayoutFee is RegistryTest {
    address[] public actors = [board, programCommittee];

    // test to set fee for an entity type
    function testFuzz_SetDefaultPayoutFee(uint32 _fee, uint256 _actor, address _manager) public {
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.expectEmit(true, false, false, true);
        emit DefaultPayoutFeeSet(FundType, _fee);
        vm.prank(actor);
        globalTestRegistry.setDefaultPayoutFee(FundType, _fee);
        assertEq(globalTestRegistry.getPayoutFee(_fund), _fee);
    }

    // Test that an unmapped default fee causes the return of max value
    function testFuzz_UnmappedDefaultPayoutFee(address _manager) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        assertEq(globalTestRegistry.getPayoutFee(_fund), type(uint32).max);
    }

    // Test zeroing the fee.
    function testFuzz_SetDefaultPayoutFeeToNoFee(uint256 _actor, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.expectEmit(true, false, false, true);
        emit DefaultPayoutFeeSet(OrgType, 0);
        vm.prank(actor);
        globalTestRegistry.setDefaultPayoutFee(OrgType, 0);
        assertEq(globalTestRegistry.getPayoutFee(_org), 0);
    }

    // test maxing fee via setting value to maxint
    function testFuzz_SetDefaultPayoutFeeToMax(uint256 _actor, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.expectEmit(true, false, false, true);
        emit DefaultPayoutFeeSet(OrgType, type(uint32).max);
        vm.prank(actor);
        globalTestRegistry.setDefaultPayoutFee(OrgType, type(uint32).max);
        assertEq(globalTestRegistry.getPayoutFee(_org), type(uint32).max);
    }

    // Test that an unauthorized user  cannot set the fee.
    function testFuzz_SetDefaultPayoutFeeUnauthorized(uint8 _entityType, uint32 _fee) public {
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setDefaultPayoutFee(_entityType, _fee);
    }
}

// Tests to verify that permissioned addresses can set the payout fee override for specific entities.
// This is accomplished by setting the default payout fee for an entity type, then setting an override for a specific entity
// then verifying that the specific entity got the override correctly set and another entity correctly had the default fee.
// These tests also verify the fee "flip" logic.
contract RegistrySetPayoutFeeOverride is RegistryTest {
    address[] public actors = [board, programCommittee];

    // test that fee override for a specific receiving entity causes the fetch of the overridden fee
    function testFuzz_SetPayoutFeeOverride(uint32 _fee, uint256 _actor, address _manager1, address _manager2) public {
        vm.assume(_fee < type(uint32).max);
        address actor = actors[_actor % actors.length];
        Fund _fund1 = orgFundFactory.deployFund(_manager1, "salt");
        Fund _fund2 = orgFundFactory.deployFund(_manager2, "salt2");
        vm.startPrank(actor);
        vm.expectEmit(true, false, false, true);
        emit DefaultPayoutFeeSet(FundType, _fee + 1);
        globalTestRegistry.setDefaultPayoutFee(FundType, _fee + 1);
        vm.expectEmit(true, false, false, false);
        emit PayoutFeeOverrideSet(address(_fund1), _fee);
        globalTestRegistry.setPayoutFeeOverride(_fund1, _fee);
        vm.stopPrank();
        assertEq(globalTestRegistry.getPayoutFeeWithOverrides(_fund1), _fee);
        assertEq(globalTestRegistry.getPayoutFeeWithOverrides(_fund2), _fee + 1);
    }

    // test zeroing the override for a specific receiving entity triggers an override of no fee
    function testFuzz_SetPayoutFeeOverrideToNoFee(uint256 _actor, bytes32 _orgId1, bytes32 _orgId2) public {
        vm.assume(_orgId1 != _orgId2);
        address actor = actors[_actor % actors.length];
        Org _org1 = orgFundFactory.deployOrg(_orgId1);
        Org _org2 = orgFundFactory.deployOrg(_orgId2);
        vm.startPrank(actor);
        vm.expectEmit(true, false, false, true);
        emit DefaultPayoutFeeSet(OrgType, 10);
        globalTestRegistry.setDefaultPayoutFee(OrgType, 10);
        vm.expectEmit(true, false, false, true);
        emit PayoutFeeOverrideSet(address(_org1), 0);
        globalTestRegistry.setPayoutFeeOverride(_org1, 0);
        vm.stopPrank();
        assertEq(globalTestRegistry.getPayoutFeeWithOverrides(_org1), 0);
        assertEq(globalTestRegistry.getPayoutFeeWithOverrides(_org2), 10);
    }

    // test that not setting the override for a specific receiving entity causes getPayoutFeeWithOverrides to return the default fee
    function testFuzz_SetPayoutFeeOverrideNotDoneYieldsDefaultFee(uint256 _actor, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.startPrank(actor);
        vm.expectEmit(true, false, false, true);
        emit DefaultPayoutFeeSet(OrgType, 10);
        globalTestRegistry.setDefaultPayoutFee(OrgType, 10);
        vm.stopPrank();
        assertEq(globalTestRegistry.getPayoutFeeWithOverrides(_org), 10);
    }

    // test that an unauthorized user  cannot set the fee override
    function testFuzz_SetPayoutFeeOverrideUnauthorized(address _manager, uint32 _fee) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setPayoutFeeOverride(_fund, _fee);
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
    function testFuzz_SetDefaultTransferFee(uint32 _fee, uint256 _actor, address _manager, bytes32 _orgId) public {
        vm.assume((_fee > 0) && (_fee < (type(uint32).max)));
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, _fee);
        vm.prank(actor);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, _fee);
        assertEq(globalTestRegistry.getTransferFee(_fund, _org), _fee);
    }

    // Test that an unmapped default fee causes the return of max value
    function testFuzz_UnmappedDefaultTransferFee(address _manager, bytes32 _orgId) public {
        Org org = orgFundFactory.deployOrg(_orgId);
        Fund fund = orgFundFactory.deployFund(_manager, "salt");
        assertEq(globalTestRegistry.getTransferFee(fund, org), type(uint32).max);
    }

    // test zeroing the default transfer fee between 2 entity types
    function testFuzz_SetDefaultTransferFeeNoFee(uint256 _actor, address _manager, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, 0);
        vm.prank(actor);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, 0);
        assertEq(globalTestRegistry.getTransferFee(_fund, _org), 0);
    }

    // test maxing the default transfer fee between 2 entity types
    function testFuzz_SetDefaultTransferFeeToMax(uint256 _actor, address _manager, bytes32 _orgId) public {
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId);
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
    function testFuzz_SetTransferFeeSenderOverride(
        uint32 _fee,
        uint256 _actor,
        address _manager1,
        address _manager2,
        bytes32 _orgId
    ) public {
        vm.assume(_manager1 != _manager2);
        vm.assume((_fee > 0) && (_fee < (type(uint32).max - 1)));
        address actor = actors[_actor % actors.length];
        Fund _fund1 = orgFundFactory.deployFund(_manager1, "salt");
        Fund _fund2 = orgFundFactory.deployFund(_manager2, "salt2");
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.startPrank(actor);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, _fee + 1);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, _fee + 1);
        vm.expectEmit(true, true, false, false);
        emit TransferFeeSenderOverrideSet(address(_fund1), OrgType, _fee);
        globalTestRegistry.setTransferFeeSenderOverride(_fund1, OrgType, _fee);
        vm.stopPrank();
        assertEq(globalTestRegistry.getTransferFeeWithOverrides(_fund1, _org), _fee);
        assertEq(globalTestRegistry.getTransferFeeWithOverrides(_fund2, _org), _fee + 1);
    }

    // test the setting of the transfer fee sender override for an entity to zero
    function testFuzz_SetTransferFeeSenderOverrideToNoFee(
        uint256 _actor,
        address _manager1,
        address _manager2,
        bytes32 _orgId
    ) public {
        vm.assume(_manager1 != _manager2);
        address actor = actors[_actor % actors.length];
        Fund _fund1 = orgFundFactory.deployFund(_manager1, "salt");
        Fund _fund2 = orgFundFactory.deployFund(_manager2, "salt2");
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.startPrank(actor);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, 10);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, 10);
        vm.expectEmit(true, true, false, false);
        emit TransferFeeSenderOverrideSet(address(_fund1), OrgType, 0);
        globalTestRegistry.setTransferFeeSenderOverride(_fund1, OrgType, 0);
        vm.stopPrank();
        assertEq(globalTestRegistry.getTransferFeeWithOverrides(_fund1, _org), 0);
        assertEq(globalTestRegistry.getTransferFeeWithOverrides(_fund2, _org), 10);
    }

    // test that not setting transfer overrides getTransferFeeWithOverrides to return the default fee
    function testFuzz_SetTransferFeeOverrideNotDoneYeildsDefaultFee(uint256 _actor, address _manager, bytes32 _orgId)
        public
    {
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.startPrank(actor);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, 10);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, 10);
        vm.stopPrank();
        assertEq(globalTestRegistry.getTransferFeeWithOverrides(_fund, _org), 10);
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
    function testFuzz_SetTransferFeeReceiverOverride(
        uint32 _fee,
        uint256 _actor,
        address _manager,
        bytes32 _orgId1,
        bytes32 _orgId2
    ) public {
        vm.assume(_orgId1 != _orgId2);
        vm.assume((_fee > 0) && (_fee < (type(uint32).max - 1)));
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org1 = orgFundFactory.deployOrg(_orgId1);
        Org _org2 = orgFundFactory.deployOrg(_orgId2);
        vm.startPrank(actor);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, _fee + 1);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, _fee + 1);
        vm.expectEmit(true, true, false, false);
        emit TransferFeeReceiverOverrideSet(FundType, address(_org1), _fee);
        globalTestRegistry.setTransferFeeReceiverOverride(FundType, _org1, _fee);
        vm.stopPrank();
        assertEq(globalTestRegistry.getTransferFeeWithOverrides(_fund, _org1), _fee);
        assertEq(globalTestRegistry.getTransferFeeWithOverrides(_fund, _org2), _fee + 1);
    }

    // test the setting of the transfer fee receiver override for an entity to zero
    function testFuzz_SetTransferFeeReceiverOverrideToNoFee(
        uint256 _actor,
        address _manager,
        bytes32 _orgId1,
        bytes32 _orgId2
    ) public {
        vm.assume(_orgId1 != _orgId2);
        address actor = actors[_actor % actors.length];
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org1 = orgFundFactory.deployOrg(_orgId1);
        Org _org2 = orgFundFactory.deployOrg(_orgId2);
        vm.startPrank(actor);
        vm.expectEmit(true, true, false, false);
        emit DefaultTransferFeeSet(FundType, OrgType, 10);
        globalTestRegistry.setDefaultTransferFee(FundType, OrgType, 10);
        vm.expectEmit(true, true, false, false);
        emit TransferFeeReceiverOverrideSet(FundType, address(_org1), 0);
        globalTestRegistry.setTransferFeeReceiverOverride(FundType, _org1, 0);
        vm.stopPrank();
        assertEq(globalTestRegistry.getTransferFeeWithOverrides(_fund, _org1), 0);
        assertEq(globalTestRegistry.getTransferFeeWithOverrides(_fund, _org2), 10);
    }

    // test that an unauthorized user  cannot set the transfer fee sender override
    function testFuzz_SetTransferFeeReceiverOverrideUnauthorized(uint32 _fee, bytes32 _orgId) public {
        Org _org = orgFundFactory.deployOrg(_orgId);
        vm.expectRevert(Unauthorized.selector);
        globalTestRegistry.setTransferFeeReceiverOverride(FundType, _org, _fee);
    }
}
