// SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";

import { OrgFundFactory } from "../OrgFundFactory.sol";
import { Org } from "../Org.sol";
import { Fund } from "../Fund.sol";

contract OrgFundFactoryTest is DeployTest {
    event EntityDeployed(address indexed entity, uint8 indexed entityType, address indexed entityManager);
}

contract OrgFundFactoryConstructor is OrgFundFactoryTest {
    function test_OrgFundFactoryConstructor() public {
        OrgFundFactory _orgFundFactory = new OrgFundFactory(globalTestRegistry);
        assertEq(_orgFundFactory.registry(), globalTestRegistry);
    }
}

contract OrgFundFactoryDeployOrgTest is OrgFundFactoryTest {
    function testFuzz_DeployOrg(bytes32 _orgId, bytes32 _salt) public {
        address _expectedContractAddress = orgFundFactory.computeOrgAddress(_salt);
        vm.expectEmit(true, true, true, false);
        emit EntityDeployed(_expectedContractAddress, 1, address(0));
        Org _org = orgFundFactory.deployOrg(_orgId, _salt);
        assertEq(_org.orgId(), _orgId);
        assertEq(globalTestRegistry, _org.registry());
        assertEq(_org.entityType(), 1);
        assertEq(_org.manager(), address(0));
        assertEq(_expectedContractAddress, address(_org));
    }

    function testFuzz_DeployOrgFailDuplicate(bytes32 _orgId, bytes32 _salt) public {
        orgFundFactory.deployOrg(_orgId, _salt);
        vm.expectRevert("ERC1167: create2 failed");
        orgFundFactory.deployOrg(_orgId, _salt);
    }

    function testFuzz_DeployOrgFailNonWhiteListedFactory(bytes32 _orgId, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory2.deployOrg(_orgId, _salt);
    }

    function testFuzz_DeployOrgFailAfterUnwhitelisting(bytes32 _orgId, bytes32 _salt) public {
        bytes32 _salt2 = keccak256(abi.encode(_salt));
        vm.assume(_orgId != "1234");
        orgFundFactory.deployOrg(_orgId, _salt);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), false);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory.deployOrg("1234", _salt2);
    }

    function testFuzz_DeployOrgFromFactory2(bytes32 _orgId, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory2), true);
        address _expectedContractAddress = orgFundFactory2.computeOrgAddress(_salt);
        vm.expectEmit(true, true, true, false);
        emit EntityDeployed(_expectedContractAddress, 1, address(0));
        Org _org = orgFundFactory2.deployOrg(_orgId, _salt);
        assertEq(_org.orgId(), _orgId);
        assertEq(globalTestRegistry, _org.registry());
        assertEq(_org.entityType(), 1);
        assertEq(_expectedContractAddress, address(_org));
    }
}

contract OrgFundFactoryDeployFundTest is OrgFundFactoryTest {
    function testFuzz_DeployFund(address _manager, bytes32 _salt) public {
        address _expectedContractAddress = orgFundFactory.computeFundAddress(_salt);
        vm.expectEmit(true, true, true, false);
        emit EntityDeployed(_expectedContractAddress, 2, _manager);
        Fund _fund = orgFundFactory.deployFund(_manager, _salt);
        assertEq(globalTestRegistry, _fund.registry());
        assertEq(_fund.entityType(), 2);
        assertEq(_fund.manager(), _manager);
        assertEq(_expectedContractAddress, address(_fund));
    }

    function testFuzz_DeployFundDuplicateFail(address _manager, bytes32 _salt) public {
        orgFundFactory.deployFund(_manager, _salt);
        vm.expectRevert("ERC1167: create2 failed");
        orgFundFactory.deployFund(_manager, _salt);
    }

    function testFuzz_DeployFundFailNonWhiteListedFactory(address _manager, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory2.deployFund(_manager, _salt);
    }

    function testFuzz_DeployFundFailAfterUnwhitelisting(address _manager, bytes32 _salt) public {
        bytes32 _salt2 = keccak256(abi.encode(_salt));
        vm.assume(_manager != address(1234));
        orgFundFactory.deployFund(_manager, _salt);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), false);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory.deployFund(address(1234), _salt2);
    }

    function testFuzz_DeployFundFromFactory2(address _manager, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory2), true);
        address _expectedContractAddress = orgFundFactory2.computeFundAddress(_salt);
        vm.expectEmit(true, true, true, false);
        emit EntityDeployed(_expectedContractAddress, 2, _manager);
        Fund _fund = orgFundFactory2.deployFund(_manager, _salt);
        assertEq(globalTestRegistry, _fund.registry());
        assertEq(_fund.entityType(), 2);
        assertEq(_expectedContractAddress, address(_fund));
    }
}
