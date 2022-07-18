// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "./utils/DeployTest.sol";
import "../Registry.sol";

import "../Org.sol";
import "../Fund.sol";

contract OrgTest is DeployTest {
    // Shadows EndaomentAuth.
    error AlreadyInitialized();

    Org public org;

    function setUp() public override {
        super.setUp();
        org = new Org();
        org.initialize(globalTestRegistry, bytes32("11-11-1111"));
    }
}

contract OrgInitializer is OrgTest {
    function testFuzz_OrgInitializer(bytes32 _orgId) public {
        Org _org = new Org();
        _org.initialize(globalTestRegistry, _orgId);
        assertEq(_org.entityType(), 1);
        assertEq(_org.manager(), address(0));
        assertEq(_org.orgId(), _orgId);
    }

    function testFuzz_CannotCallOrgInitializerTwice(bytes32 _orgId) public {
        Org _org = new Org();
        _org.initialize(globalTestRegistry, _orgId);

        // Attempt to call Org initializer
        vm.expectRevert(AlreadyInitialized.selector);
        _org.initialize(globalTestRegistry, bytes32("newId"));

        // Attempt to call EndaomentAuth initializer
        vm.expectRevert(AlreadyInitialized.selector);
        _org.initialize(globalTestRegistry, bytes32("beef_cafe"));

        assertEq(_org.entityType(), 1);
        assertEq(_org.manager(), address(0));
        assertEq(_org.orgId(), _orgId);
    }
}

contract OrgSetOrgId is OrgTest {
    address[] public actors = [board, capitalCommittee];

    function testFuzz_SetOrgId(address _manager, bytes32 _newOrgId, uint256 _actor) public {
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

contract FundInitializer is DeployTest {
    // Shadows EndaomentAuth.
    error AlreadyInitialized();

    function testFuzz_FundInitializer(address _manager) public {
        Fund _fund = new Fund();
        _fund.initialize(globalTestRegistry, _manager);
        assertEq(_fund.entityType(), 2);
        assertEq(_fund.manager(), _manager);
    }

    function testFuzz_CannotCallFundInitializerTwice(address _manager) public {
        Fund _fund = new Fund();
        _fund.initialize(globalTestRegistry, _manager);

        // Attempt to call Entity initializer
        vm.expectRevert(AlreadyInitialized.selector);
        _fund.initialize(globalTestRegistry, address(0xbeefcafe));

        assertEq(_fund.entityType(), 2);
        assertEq(_fund.manager(), _manager);
    }
}
