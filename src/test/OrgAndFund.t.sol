// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";

import "../Org.sol";
import "../Fund.sol";

contract OrgTest is DeployTest {
    Org public org;
    function setUp() public override {
        super.setUp();
        org = new Org(globalTestRegistry, "11-11-1111");
    }
}

contract OrgConstructor is OrgTest {
    function testFuzz_OrgConstructor(bytes32 _orgId) public {
        Org _org = new Org(globalTestRegistry, _orgId);
        assertEq(_org.entityType(), 1);
    }
}

contract OrgSetOrgId is OrgTest {
    address[] public actors = [board, capitalCommittee];
    
    function testFuzz_SetOrgId(address _manager, bytes32 _newOrgId, uint _actor) public {
        address actor = actors[_actor % actors.length];
        vm.prank(board);
        org.setManager(_manager);
        vm.prank(actor);
        org.setOrgId(_newOrgId);
        assertEq(org.orgId(), _newOrgId);
    }

    function testFuzz_SetOrgIdUnauthorized(address _manager, bytes32 _newOrgId) public {
        vm.prank(board);
        org.setManager(_manager);
        vm.expectRevert(Unauthorized.selector);
        org.setOrgId(_newOrgId);
    }
}

contract FundTest is DeployTest {
}

contract FundConstructor is FundTest {
    function testFuzz_FundConstructor(address _manager) public {
        Fund _fund = new Fund(globalTestRegistry, _manager);
        assertEq(_fund.entityType(), 2);
    }
}
