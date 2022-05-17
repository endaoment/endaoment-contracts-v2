// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { Auth, Authority } from "../lib/auth/Auth.sol";
import { RolesAuthority } from "../lib/auth/authorities/RolesAuthority.sol";
import { EndaomentAuth } from "../lib/auth/EndaomentAuth.sol";

import "forge-std/Test.sol";

import "forge-std/console2.sol";

error AlreadyInitialized();
error Unauthorized();

// Mock Roles Authority contract to be used in all EndaomentAuth tests below
contract RolesAuthorityMock is RolesAuthority {
    // --- Constructor ---
    constructor(address _admin) RolesAuthority(_admin, Authority(address(this))) {
    }
}

// Mock EndaomentAuth contracts for target tests
contract EndaomentAuthInstanceA is EndaomentAuth {
    constructor(RolesAuthority _authority) {
        initialize(_authority, "special target");
    }

    function mockInstanceFunctionMulBy2(uint256 i) public view requiresAuth returns(uint256) {
        return (i * 2);
    }
}

contract EndaomentAuthInstanceB is EndaomentAuth {
    constructor(RolesAuthority _authority) {
        initialize(_authority, "special target");
    }

    function mockInstanceFunctionMulBy3(uint256 i) public view requiresAuth returns(uint256) {
        return (i * 3);
    }
}

contract EndaomentAuthInstanceNoTarget is EndaomentAuth {
    constructor(RolesAuthority _authority) {
        initialize(_authority, "");
    }

    function mockInstanceFunctionDivBy2(uint256 i) public view requiresAuth returns(uint256) {
        return (i / 2);
    }
}

// Base test contract to setup tests
contract EndaomentAuthTest is Test {
    address admin = address(0xad);
    address newAdmin = address(0xda);
    RolesAuthorityMock roleAuth;
    EndaomentAuthInstanceA instanceA;
    EndaomentAuthInstanceB instanceB;
    EndaomentAuthInstanceNoTarget instanceNoTarget;

    function setUp() public virtual {
        roleAuth = new RolesAuthorityMock(admin);
        instanceA = new EndaomentAuthInstanceA(roleAuth);
        instanceB = new EndaomentAuthInstanceB(roleAuth);
        instanceNoTarget = new EndaomentAuthInstanceNoTarget(roleAuth);
        vm.label(admin, "admin");
        vm.label(address(roleAuth), "roleAuth");
        vm.label(address(instanceA), "instanceA");
        vm.label(address(instanceB), "instanceB");
        vm.label(address(instanceNoTarget), "instanceNoTarget");
    }
}

// "Special target" tests.
contract EndaomentAuthReInitTest is EndaomentAuthTest {
    function test_EndaomentAuthFailReInit() public {
        // Call to Fund / EndaomentAuth's initialize function another time since setUp to verify it fails in that it can't be called again
        vm.expectRevert(AlreadyInitialized.selector);
        instanceA.initialize(roleAuth, "special target");
    }

    function test_EndaomentAuthFailReInitWithNoSpecialTarget() public {
        // Call to Fund / EndaomentAuth's initialize function another time since setUp to verify it fails in that it can't be called again
        vm.expectRevert(AlreadyInitialized.selector);
        instanceNoTarget.initialize(roleAuth, "");
    }
}

contract EndaomentAuthPermissionsTest is EndaomentAuthTest {
    address authorizedUser = address(0xaa);
    address unAuthorizedUser = address(0xab);
    address authorizedNoTargetUser = address(0xcd);

    function setUp() public override {
        super.setUp();
        address mockInstanceTarget = address(bytes20("special target"));
        bytes4  mockInstanceAFunction = bytes4(keccak256("mockInstanceFunctionMulBy2(uint256)"));
        bytes4  mockInstanceBFunction = bytes4(keccak256("mockInstanceFunctionMulBy3(uint256)"));
        bytes4  mockInstanceNoTargetFunction = bytes4(keccak256("mockInstanceFunctionDivBy2(uint256)"));
        // role setup for authorized users
        vm.startPrank(admin);
        roleAuth.setRoleCapability(1, mockInstanceTarget, mockInstanceAFunction, true);
        roleAuth.setRoleCapability(1, mockInstanceTarget, mockInstanceBFunction, true);
        roleAuth.setUserRole(authorizedUser, 1, true);
        roleAuth.setRoleCapability(2, address(instanceNoTarget), mockInstanceNoTargetFunction, true);
        roleAuth.setUserRole(authorizedNoTargetUser, 2, true);
        vm.stopPrank();
    }

    // "Special target" tests.
    function testAuhorizedUserCanCallInstanceFunctionsViaSpecialTarget() public {
        vm.startPrank(authorizedUser);
        uint256 retvalA = instanceA.mockInstanceFunctionMulBy2(7);
        assertEq(retvalA, 14);
        uint256 retvalB = instanceB.mockInstanceFunctionMulBy3(7);
        assertEq(retvalB, 21);
        vm.stopPrank();
    }

    function testUnauhorizedUserCannotCallInstanceFunctionsViaSpecialTarget() public {
        vm.startPrank(unAuthorizedUser);
        vm.expectRevert(Unauthorized.selector);
        instanceA.mockInstanceFunctionMulBy2(7);
        vm.expectRevert(Unauthorized.selector);
        instanceB.mockInstanceFunctionMulBy3(7);
        vm.stopPrank();
    }

    function testAuhorizedButRevokedUserCannotCallInstanceFunctionsViaSpecialTarget() public {
        vm.prank(admin);
        roleAuth.setUserRole(authorizedUser, 1, false);
        vm.startPrank(authorizedUser);
        vm.expectRevert(Unauthorized.selector);
        instanceA.mockInstanceFunctionMulBy2(7);
        vm.expectRevert(Unauthorized.selector);
        instanceB.mockInstanceFunctionMulBy3(7);
        vm.stopPrank();
    }

    function testRoleAuthorityOwnerCanCallInstanceFunctionsViaSpecialTarget() public {
        vm.startPrank(admin);
        uint256 retvalA = instanceA.mockInstanceFunctionMulBy2(5);
        assertEq(retvalA, 10);
        uint256 retvalB = instanceB.mockInstanceFunctionMulBy3(5);
        assertEq(retvalB, 15);
        vm.stopPrank();
    }

    function testNewRoleAuthorityOwnerPermissionsTransfer() public {
        vm.prank(admin);
        roleAuth.setOwner(newAdmin);
        vm.startPrank(newAdmin);
        uint256 retvalA = instanceA.mockInstanceFunctionMulBy2(5);
        assertEq(retvalA, 10);
        uint256 retvalB = instanceB.mockInstanceFunctionMulBy3(5);
        assertEq(retvalB, 15);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.expectRevert(Unauthorized.selector);
        instanceA.mockInstanceFunctionMulBy2(7);
        vm.expectRevert(Unauthorized.selector);
        instanceB.mockInstanceFunctionMulBy3(7);
        vm.stopPrank();
    }

    // No "Special Target" tests.
    function testAuhorizedUserCanCallInstanceFunctionsWithNoSpecialTarget() public {
        vm.startPrank(authorizedNoTargetUser);
        uint256 retval = instanceNoTarget.mockInstanceFunctionDivBy2(10);
        assertEq(retval, 5);
        vm.stopPrank();
    }

    function testUnauhorizedUserCannotCallInstanceFunctionsWithNoSpecialTarget() public {
        vm.startPrank(unAuthorizedUser);
        vm.expectRevert(Unauthorized.selector);
        instanceNoTarget.mockInstanceFunctionDivBy2(10);
        vm.stopPrank();
    }

    function testAuhorizedButRevokedUserCannotCallInstanceFunctionsWithNoSpecialTarget() public {
        vm.prank(admin);
        roleAuth.setUserRole(authorizedNoTargetUser, 2, false);
        vm.startPrank(authorizedNoTargetUser);
        vm.expectRevert(Unauthorized.selector);
        instanceNoTarget.mockInstanceFunctionDivBy2(10);
        vm.stopPrank();
    }

    function testRoleAuthorityOwnerCanCallInstanceFunctionsWithNoSpecialTarget() public {
        vm.startPrank(admin);
        uint256 retval = instanceNoTarget.mockInstanceFunctionDivBy2(10);
        assertEq(retval, 5);
        vm.stopPrank();
    }

    function testNewRoleAuthorityOwnerPermissionsTransferWithNoSpecialTarget() public {
        vm.prank(admin);
        roleAuth.setOwner(newAdmin);
        vm.startPrank(newAdmin);
        uint256 retval = instanceNoTarget.mockInstanceFunctionDivBy2(10);
        assertEq(retval, 5);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.expectRevert(Unauthorized.selector);
        instanceNoTarget.mockInstanceFunctionDivBy2(10);
        vm.stopPrank();
    }
}


