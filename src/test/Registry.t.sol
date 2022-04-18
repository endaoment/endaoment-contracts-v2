// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import { Registry } from "../Registry.sol";
import { OrgFundFactory } from "../OrgFundFactory.sol";
import { Org } from "../Org.sol";
import { Fund } from "../Fund.sol";

contract RegistryTest is DeployTest {
    event FactoryApprovalSet(address indexed factory, bool isApproved);
    event EntityStatusSet(address indexed entity, bool isActive);
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
        vm.expectEmit(true, false, false, false);
        emit FactoryApprovalSet(_factoryAddress, true);
        vm.prank(admin);
        globalTestRegistry.setFactoryApproval(address(_factoryAddress), true);
        assertTrue(globalTestRegistry.isApprovedFactory(_factoryAddress));
    }

    function testFuzz_SetFactoryApprovalFalse(address _factoryAddress) public {
        vm.expectEmit(true, false, false, false);
        emit FactoryApprovalSet(_factoryAddress, false);
        vm.prank(admin);
        globalTestRegistry.setFactoryApproval(_factoryAddress, false);
        assertFalse(globalTestRegistry.isApprovedFactory(_factoryAddress));
    }

    function testFuzz_SetFactoryApprovalUnauthorized(address _factoryAddress) public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        globalTestRegistry.setFactoryApproval(_factoryAddress, true);
    }
}

contract RegistrySetEntityStatus is RegistryTest {
    OrgFundFactory orgFundFactory;

    function setUp() public override {
        super.setUp();
        orgFundFactory = new OrgFundFactory(globalTestRegistry);
        vm.prank(admin);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), true);
    }

    function testFuzz_SetEntityStatusTrue(address _manager) public {
        Fund _fund = orgFundFactory.deployFund(_manager, "salt");
        vm.expectEmit(true, false, false, false);
        emit EntityStatusSet(address(_fund), true);
        vm.prank(admin);
        globalTestRegistry.setEntityStatus(_fund, true);
    }

    function testFuzz_SetEntityStatusFalse(bytes32 _orgId) public {
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.expectEmit(true, false, false, false);
        emit EntityStatusSet(address(_org), false);
        vm.prank(admin);
        globalTestRegistry.setEntityStatus(_org, false);
    }

    function testFuzz_SetEntityStatusUnauthorized(bytes32 _orgId) public {
        Org _org = orgFundFactory.deployOrg(_orgId, "salt");
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        globalTestRegistry.setEntityStatus(_org, false);
    }
}
