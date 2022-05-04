// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { DeployTest } from "./utils/DeployTest.sol";

contract NDAOTest is DeployTest {
    error Unauthorized();
    bytes ErrorUnauthorized = abi.encodeWithSelector(Unauthorized.selector);
}

contract Deployment is NDAOTest {

    function test_Deployment() public {
        assertEq(ndao.name(), "NDAO");
        assertEq(ndao.symbol(), "NDAO");
        assertEq(ndao.decimals(), 18);
        assertEq(address(ndao.authority()), address(globalTestRegistry));
    }
}

contract Minting is NDAOTest {
    address[] public actors = [board, capitalCommittee];

    function getAuthorizedActor(uint256 _seed) public returns (address) {
        uint256 _index = bound(_seed, 0, actors.length - 1);
        return actors[_index];
    }

    function testFuzz_AllowsAuthorizedToMint(address _to, uint256 _amount, uint256 _seed) public {
        address _actor = getAuthorizedActor(_seed);
        uint256 _initialBalance = ndao.balanceOf(_to);

        vm.prank(_actor);
        ndao.mint(_to, _amount);

        assertEq(ndao.balanceOf(_to) - _initialBalance, _amount);
    }

    function testFuzz_AllowsMultipleMints(address _to, uint256 _amount1, uint256 _amount2, uint256 _seed) public {
        address _actor = getAuthorizedActor(_seed);
        _amount1 = bound(_amount1, 0, type(uint128).max);
        _amount2 = bound(_amount2, 0, type(uint128).max);

        uint256 _initialBalance = ndao.balanceOf(_to);

        vm.prank(_actor);
        ndao.mint(_to, _amount1);
        assertEq(ndao.balanceOf(_to) - _initialBalance, _amount1);

        vm.prank(_actor);
        ndao.mint(_to, _amount2);
        assertEq(ndao.balanceOf(_to) - _initialBalance, _amount1 + _amount2);
    }

    function testFuzz_AllowsMintToMultipleAddresses(
        address _to1,
        address _to2,
        uint256 _amount1,
        uint256 _amount2,
        uint256 _seed
    ) public {
        vm.assume(_to1 != _to2);
        address _actor = getAuthorizedActor(_seed);
        _amount1 = bound(_amount1, 0, type(uint128).max);
        _amount2 = bound(_amount2, 0, type(uint128).max);

        uint256 _to1InitialBalance = ndao.balanceOf(_to1);
        uint256 _to2InitialBalance = ndao.balanceOf(_to2);

        vm.startPrank(_actor);
        ndao.mint(_to1, _amount1);
        ndao.mint(_to2, _amount2);
        vm.stopPrank();

        assertEq(ndao.balanceOf(_to1) - _to1InitialBalance, _amount1);
        assertEq(ndao.balanceOf(_to2) - _to2InitialBalance, _amount2);
    }

    function testFuzz_DoesNotAllowNonAuthorizedAccountToMint(address _notAdmin, address _to, uint256 _amount) public {
        vm.assume(
            _notAdmin != board &&
            _notAdmin != capitalCommittee
        );

        vm.prank(_notAdmin);
        vm.expectRevert(ErrorUnauthorized);
        ndao.mint(_to, _amount);
    }

    function testFuzz_DoesNotAllowMintAfterCapabilityRemoved(address _to, uint256 _amount) public {
        vm.prank(board);
        globalTestRegistry.setRoleCapability(22, address(ndao), ndaoMint, false);

        vm.prank(capitalCommittee);
        vm.expectRevert(ErrorUnauthorized);
        ndao.mint(_to, _amount);
    }

    function testFuzz_DoesNotAllowMintAfterRoleRemoved(address _to, uint256 _amount) public {
        vm.prank(board);
        globalTestRegistry.setUserRole(capitalCommittee, 22, false);

        vm.prank(capitalCommittee);
        vm.expectRevert(ErrorUnauthorized);
        ndao.mint(_to, _amount);
    }
}
