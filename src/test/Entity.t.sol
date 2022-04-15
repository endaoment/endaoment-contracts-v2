// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";

import { EntityInactive, InsufficientFunds } from "../Entity.sol";
import { OrgFundFactory } from "../OrgFundFactory.sol";
import { Fund } from "../Fund.sol";
import { Org } from "../Org.sol";

contract EntityTest is DeployTest {
    OrgFundFactory orgFundFactory;
    function setUp() public override {
        super.setUp();
        orgFundFactory = new OrgFundFactory(globalTestRegistry);
        vm.prank(admin);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), true);
    }
}

contract EntityDonate is EntityTest {
    function testFuzz_DonateFailInactive(address _manager, address _donator) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.prank(admin);
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
        vm.startPrank(admin);
        globalTestRegistry.setEntityStatus(_fund, false);
        globalTestRegistry.setEntityStatus(_org, true);
        vm.stopPrank();
        vm.prank(_manager);
        vm.expectRevert(abi.encodeWithSelector(EntityInactive.selector));
        _fund.transfer(_org, 1);
    }

    function testFuzz_TransferFailUnauthorized(address _manager, bytes32 _orgId) public {
        vm.assume(msg.sender != _manager);
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.startPrank(admin);
        globalTestRegistry.setEntityStatus(_fund, true);
        globalTestRegistry.setEntityStatus(_org, true);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        _fund.transfer(_org, 1);
    }

    function testFuzz_TransferFailInsufficientfunds(address _manager, bytes32 _orgId) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.startPrank(admin);
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
