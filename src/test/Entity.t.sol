// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";

import { EntityInactive, InsufficientFunds } from "../Entity.sol";
import { OrgFundFactory } from "../OrgFundFactory.sol";
import { Fund } from "../Fund.sol";
import { Org } from "../Org.sol";

contract EntityTest is DeployTest {
    event EntityManagerSet(address indexed oldManager, address indexed newManager);
}

contract EntitySetManager is EntityTest {
    address[] public actors = [board, capitalCommittee];
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
        vm.expectEmit(true, false, false, false);
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

contract EntityDonate is EntityTest {
    function testFuzz_DonateFailInactive(address _manager, address _donator) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.prank(board);
        globalTestRegistry.setEntityStatus(_fund, false);
        vm.expectRevert(abi.encodeWithSelector(EntityInactive.selector));
        vm.prank(_donator);
        _fund.donate(1);
    }
}

contract EntityTransfer is EntityTest {
    function testFuzz_TransferFailInactive(address _manager, bytes32 _orgId) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.startPrank(board);
        globalTestRegistry.setEntityStatus(_fund, false);
        globalTestRegistry.setEntityStatus(_org, true);
        vm.stopPrank();
        vm.prank(_manager);
        vm.expectRevert(abi.encodeWithSelector(EntityInactive.selector));
        _fund.transfer(_org, 1);
    }

    function testFuzz_TransferFailUnauthorized(address _manager, bytes32 _orgId) public {
        vm.assume(msg.sender != _manager);
        vm.assume(msg.sender != capitalCommittee);
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.startPrank(board);
        globalTestRegistry.setEntityStatus(_fund, true);
        globalTestRegistry.setEntityStatus(_org, true);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        _fund.transfer(_org, 1);
    }

    function testFuzz_TransferFailInsufficientfunds(address _manager, bytes32 _orgId) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.startPrank(board);
        globalTestRegistry.setEntityStatus(_fund, true);
        globalTestRegistry.setEntityStatus(_org, true);
        vm.stopPrank();
        vm.prank(_manager);
        vm.expectRevert(abi.encodeWithSelector(InsufficientFunds.selector));
        _fund.transfer(_org, 1);
    }
}

// TODO: Above are "unhappy path" tests for Entity donations and transferas.
// TODO: When we have functions to do the setting of default and override fees, we can have "happy path" tests for those.
