// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import {Auth, Authority} from "../lib/auth/Auth.sol";
import {RolesAuthority} from "../lib/auth/authorities/RolesAuthority.sol";
import {EndaomentAuth} from "../lib/auth/EndaomentAuth.sol";

import {RegistryAuth} from "../RegistryAuth.sol";

import "forge-std/Test.sol";

import "forge-std/console2.sol";

error AlreadyInitialized();
error Unauthorized();
error OwnershipInvalid();

// Fix RegistryAuth with inputs to be used in all EndaomentAuth tests below
contract RegistryAuthFixture is RegistryAuth {
    // --- Constructor ---
    constructor(address _admin) RegistryAuth(_admin, Authority(address(this))) {}
}

// Mock EndaomentAuth contracts for target tests
contract EndaomentAuthInstanceA is EndaomentAuth {
    function initialize(RolesAuthority _authority, bytes20 _specialTarget) public {
        __initEndaomentAuth(_authority, _specialTarget);
    }

    constructor(RolesAuthority _authority) {
        initialize(_authority, "special target");
    }

    function mockInstanceFunctionMulBy2(uint256 i) public view requiresAuth returns (uint256) {
        return (i * 2);
    }
}

contract EndaomentAuthInstanceB is EndaomentAuth {
    function initialize(RolesAuthority _authority, bytes20 _specialTarget) public {
        __initEndaomentAuth(_authority, _specialTarget);
    }

    constructor(RolesAuthority _authority) {
        initialize(_authority, "special target");
    }

    function mockInstanceFunctionMulBy3(uint256 i) public view requiresAuth returns (uint256) {
        return (i * 3);
    }
}

contract EndaomentAuthInstanceNoTarget is EndaomentAuth {
    function initialize(RolesAuthority _authority, bytes20 _specialTarget) public {
        __initEndaomentAuth(_authority, _specialTarget);
    }

    constructor(RolesAuthority _authority) {
        initialize(_authority, "");
    }

    function mockInstanceFunctionDivBy2(uint256 i) public view requiresAuth returns (uint256) {
        return (i / 2);
    }
}

// Base test contract to setup tests
contract EndaomentAuthTest is Test {
    /// @notice Emitted when the first step of an ownership transfer (proposal) is done.
    event OwnershipTransferProposed(address indexed user, address indexed newOwner);

    /// @notice Emitted when the second step of an ownership transfer (claim) is done.
    event OwnershipChanged(address indexed owner, address indexed newOwner);

    address admin = address(0xad);
    address newAdmin = address(0xda);
    RegistryAuthFixture registryAuth;
    EndaomentAuthInstanceA instanceA;
    EndaomentAuthInstanceB instanceB;
    EndaomentAuthInstanceNoTarget instanceNoTarget;

    function setUp() public virtual {
        registryAuth = new RegistryAuthFixture(admin);
        instanceA = new EndaomentAuthInstanceA(registryAuth);
        instanceB = new EndaomentAuthInstanceB(registryAuth);
        instanceNoTarget = new EndaomentAuthInstanceNoTarget(registryAuth);
        vm.label(admin, "admin");
        vm.label(address(registryAuth), "registryAuth");
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
        instanceA.initialize(registryAuth, "special target");
    }

    function test_EndaomentAuthFailReInitWithNoSpecialTarget() public {
        // Call to Fund / EndaomentAuth's initialize function another time since setUp to verify it fails in that it can't be called again
        vm.expectRevert(AlreadyInitialized.selector);
        instanceNoTarget.initialize(registryAuth, "");
    }
}

contract EndaomentAuthPermissionsTest is EndaomentAuthTest {
    address authorizedUser = address(0xaa);
    address unAuthorizedUser = address(0xab);
    address authorizedNoTargetUser = address(0xcd);

    function setUp() public override {
        super.setUp();
        address mockInstanceTarget = address(bytes20("special target"));
        bytes4 mockInstanceAFunction = bytes4(keccak256("mockInstanceFunctionMulBy2(uint256)"));
        bytes4 mockInstanceBFunction = bytes4(keccak256("mockInstanceFunctionMulBy3(uint256)"));
        bytes4 mockInstanceNoTargetFunction = bytes4(keccak256("mockInstanceFunctionDivBy2(uint256)"));
        // role setup for authorized users
        vm.startPrank(admin);
        registryAuth.setRoleCapability(1, mockInstanceTarget, mockInstanceAFunction, true);
        registryAuth.setRoleCapability(1, mockInstanceTarget, mockInstanceBFunction, true);
        registryAuth.setUserRole(authorizedUser, 1, true);
        registryAuth.setRoleCapability(2, address(instanceNoTarget), mockInstanceNoTargetFunction, true);
        registryAuth.setUserRole(authorizedNoTargetUser, 2, true);
        vm.stopPrank();
    }

    // "Special target" tests.
    function test_AuthorizedUserCanCallInstanceFunctionsViaSpecialTarget() public {
        vm.startPrank(authorizedUser);
        uint256 retvalA = instanceA.mockInstanceFunctionMulBy2(7);
        assertEq(retvalA, 14);
        uint256 retvalB = instanceB.mockInstanceFunctionMulBy3(7);
        assertEq(retvalB, 21);
        vm.stopPrank();
    }

    function test_UnauthorizedUserCannotCallInstanceFunctionsViaSpecialTarget() public {
        vm.startPrank(unAuthorizedUser);
        vm.expectRevert(Unauthorized.selector);
        instanceA.mockInstanceFunctionMulBy2(7);
        vm.expectRevert(Unauthorized.selector);
        instanceB.mockInstanceFunctionMulBy3(7);
        vm.stopPrank();
    }

    function test_AuthorizedButRevokedUserCannotCallInstanceFunctionsViaSpecialTarget() public {
        vm.prank(admin);
        registryAuth.setUserRole(authorizedUser, 1, false);
        vm.startPrank(authorizedUser);
        vm.expectRevert(Unauthorized.selector);
        instanceA.mockInstanceFunctionMulBy2(7);
        vm.expectRevert(Unauthorized.selector);
        instanceB.mockInstanceFunctionMulBy3(7);
        vm.stopPrank();
    }

    function test_RoleAuthorityOwnerCanCallInstanceFunctionsViaSpecialTarget() public {
        vm.startPrank(admin);
        uint256 retvalA = instanceA.mockInstanceFunctionMulBy2(5);
        assertEq(retvalA, 10);
        uint256 retvalB = instanceB.mockInstanceFunctionMulBy3(5);
        assertEq(retvalB, 15);
        vm.stopPrank();
    }

    function test_setOwnerFails() public {
        vm.prank(admin);
        vm.expectRevert(OwnershipInvalid.selector);
        registryAuth.setOwner(newAdmin);
    }

    function test_NewRoleAuthorityOwnerPermissionsTransfer() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferProposed(admin, newAdmin);
        vm.prank(admin);
        registryAuth.transferOwnership(newAdmin);
        vm.startPrank(newAdmin);
        vm.expectEmit(true, true, false, false);
        emit OwnershipChanged(admin, newAdmin);
        registryAuth.claimOwnership();
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

    function testFuzz_NewRoleAuthorityOwnerPermissionsTransferInvalid(address _someNewAdmin, address _randomUser)
        public
    {
        vm.assume(_someNewAdmin != admin);
        vm.assume(_randomUser != _someNewAdmin);
        vm.prank(admin);
        registryAuth.transferOwnership(_someNewAdmin);
        vm.startPrank(_randomUser);
        vm.expectRevert(OwnershipInvalid.selector);
        registryAuth.claimOwnership();
        vm.stopPrank();
    }

    // No "Special Target" tests.
    function test_AuthorizedUserCanCallInstanceFunctionsWithNoSpecialTarget() public {
        vm.startPrank(authorizedNoTargetUser);
        uint256 retval = instanceNoTarget.mockInstanceFunctionDivBy2(10);
        assertEq(retval, 5);
        vm.stopPrank();
    }

    function test_UnauthorizedUserCannotCallInstanceFunctionsWithNoSpecialTarget() public {
        vm.startPrank(unAuthorizedUser);
        vm.expectRevert(Unauthorized.selector);
        instanceNoTarget.mockInstanceFunctionDivBy2(10);
        vm.stopPrank();
    }

    function test_AuthorizedButRevokedUserCannotCallInstanceFunctionsWithNoSpecialTarget() public {
        vm.prank(admin);
        registryAuth.setUserRole(authorizedNoTargetUser, 2, false);
        vm.startPrank(authorizedNoTargetUser);
        vm.expectRevert(Unauthorized.selector);
        instanceNoTarget.mockInstanceFunctionDivBy2(10);
        vm.stopPrank();
    }

    function test_RoleAuthorityOwnerCanCallInstanceFunctionsWithNoSpecialTarget() public {
        vm.startPrank(admin);
        uint256 retval = instanceNoTarget.mockInstanceFunctionDivBy2(10);
        assertEq(retval, 5);
        vm.stopPrank();
    }

    function test_NewRoleAuthorityOwnerPermissionsTransferWithNoSpecialTarget() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferProposed(admin, newAdmin);
        vm.prank(admin);
        registryAuth.transferOwnership(newAdmin);
        vm.expectEmit(true, true, false, false);
        emit OwnershipChanged(admin, newAdmin);
        vm.startPrank(newAdmin);
        registryAuth.claimOwnership();
        uint256 retval = instanceNoTarget.mockInstanceFunctionDivBy2(10);
        assertEq(retval, 5);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.expectRevert(Unauthorized.selector);
        instanceNoTarget.mockInstanceFunctionDivBy2(10);
        vm.stopPrank();
    }
}
