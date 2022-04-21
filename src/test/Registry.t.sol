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
