// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { NDAO } from "../NDAO.sol";

contract NDAOTest is DSTestPlus {
    NDAO ndao;
    address admin = address(0xAD);

    error Unauthorized();
    bytes ErrorUnauthorized = abi.encodeWithSelector(Unauthorized.selector);

    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    function setUp() public virtual {
        vm.label(admin, 'admin');
        ndao = new NDAO(admin);
    }

    function expectEvent_AdminUpdate(address oldAdmin, address newAdmin) public {
        vm.expectEmit(true, true, false, false);
        emit AdminUpdated(oldAdmin, newAdmin);
    }
}

contract Deployment is NDAOTest {

    function test_Deployment() public {
        assertEq(ndao.name(), "NDAO");
        assertEq(ndao.symbol(), "NDAO");
        assertEq(ndao.decimals(), 18);
        assertEq(ndao.admin(), admin);
    }

    function testFuzz_EmitsAdminUpdatedEventOnDeployment(address _admin) public {
        expectEvent_AdminUpdate(address(0), _admin);
        new NDAO(_admin);
    }
}

contract Minting is NDAOTest {

    function testFuzz_AllowsAdminToMint(address to, uint256 amount) public {
        uint256 initialBalance = ndao.balanceOf(to);

        vm.prank(admin);
        ndao.mint(to, amount);

        assertEq(ndao.balanceOf(to) - initialBalance, amount);
    }

    function testFuzz_AllowsAdminMultipleMints(address to, uint128 _amount1, uint128 _amount2) public {
        // upcast fuzz vars that were uint128 just to bound their range
        uint256 amount1 = _amount1;
        uint256 amount2 = _amount2;

        uint256 initialBalance = ndao.balanceOf(to);

        vm.prank(admin);
        ndao.mint(to, amount1);
        assertEq(ndao.balanceOf(to) - initialBalance, amount1);

        vm.prank(admin);
        ndao.mint(to, amount2);
        assertEq(ndao.balanceOf(to) - initialBalance, amount1 + amount2);
    }

    function testFuzz_AllowsAdminToMintToMultipleAddresses(
        address to1,
        address to2,
        uint128 _amount1,
        uint128 _amount2
    ) public {
        vm.assume(to1 != to2);
        uint256 amount1 = _amount1;
        uint256 amount2 = _amount2;

        uint256 to1InitialBalance = ndao.balanceOf(to1);
        uint256 to2InitialBalance = ndao.balanceOf(to2);

        vm.startPrank(admin);
        ndao.mint(to1, amount1);
        ndao.mint(to2, amount2);
        vm.stopPrank();

        assertEq(ndao.balanceOf(to1) - to1InitialBalance, amount1);
        assertEq(ndao.balanceOf(to2) - to2InitialBalance, amount2);
    }

    function testFuzz_DoesNotAllowNonAdminToMint(address notAdmin, address to, uint256 amount) public {
        vm.assume(notAdmin != admin);

        vm.prank(notAdmin);
        vm.expectRevert(ErrorUnauthorized);
        ndao.mint(to, amount);
    }

    function testFuzz_MintsAfterAdminUpdated(address newAdmin, address to, uint256 amount) public {
        uint256 initialBalance = ndao.balanceOf(to);

        vm.prank(admin);
        ndao.updateAdmin(newAdmin);

        vm.prank(newAdmin);
        ndao.mint(to, amount);

        assertEq(ndao.balanceOf(to) - initialBalance, amount);
    }
}

contract Admin is NDAOTest {

    function testFuzz_AdminCanTransferAdmin(address newAdmin) public {
        vm.prank(admin);
        ndao.updateAdmin(newAdmin);

        assertEq(ndao.admin(), newAdmin);
    }

    function testFuzz_EmitsAdminUpdatedEvent(address newAdmin) public {
        vm.prank(admin);
        expectEvent_AdminUpdate(admin, newAdmin);
        ndao.updateAdmin(newAdmin);
    }

    function testFuzz_NewAdminCanTransferAdmin(address newAdmin, address newNewAdmin) public {
        vm.prank(admin);
        ndao.updateAdmin(newAdmin);
        assertEq(ndao.admin(), newAdmin);

        vm.prank(newAdmin);
        ndao.updateAdmin(newNewAdmin);
        assertEq(ndao.admin(), newNewAdmin);
    }

    function testFuzz_NonAdminCannotUpdateAdmin(address notAdmin, address newAdmin) public {
        vm.assume(notAdmin != admin);

        vm.prank(notAdmin);
        vm.expectRevert(ErrorUnauthorized);
        ndao.updateAdmin(newAdmin);
    }
}
