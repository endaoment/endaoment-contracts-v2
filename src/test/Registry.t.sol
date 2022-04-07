// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";

contract RegistryTest is DeployTest {
}

contract RegistryConstructor is RegistryTest {

    function testFuzz_RegistryConstructor(address _admin, address _treasury, address _baseToken) public {
        Registry _registry = new Registry(_admin, _treasury, ERC20(_baseToken));
        assertEq(_registry.admin(), _admin);
        assertEq(_registry.treasury(), _treasury);
        assertEq(address(_registry.baseToken()), _baseToken);
    }
}

contract RegistrySetFactoryApproval is RegistryTest {

    function testFuzz_SetFactoryApprovalTrue(address _factoryAddress) public {
        vm.startPrank(admin);
        globalTestRegistry.setFactoryApproval(address(_factoryAddress), true);
        assertTrue(globalTestRegistry.isApprovedFactory(_factoryAddress));
    }

    function testFuzz_SetFactoryApprovalFalse(address _factoryAddress) public {
        vm.startPrank(admin);
        globalTestRegistry.setFactoryApproval(_factoryAddress, false);
        assertFalse(globalTestRegistry.isApprovedFactory(_factoryAddress));
    }

    function testFuzz_SetFactoryApprovalUnauthorized(address _factoryAddress) public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        globalTestRegistry.setFactoryApproval(_factoryAddress, true);
    }
}

