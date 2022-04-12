// SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";

import "../OrgFundFactory.sol";
import "../Org.sol";
import "../Fund.sol";

contract OrgFundFactoryTest is DeployTest {
    OrgFundFactory orgFundFactory;
    function setUp() public override {
        super.setUp();
        orgFundFactory = new OrgFundFactory(globalTestRegistry);
        vm.prank(admin);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), true);
    }
}

contract OrgFundFactoryConstructor is OrgFundFactoryTest {
    function test_OrgFundFactoryConstructor() public {
        OrgFundFactory _orgFundFactory = new OrgFundFactory(globalTestRegistry);
        assertEq(_orgFundFactory.registry(), globalTestRegistry);
    }
}

contract OrgFundFactoryDeployOrgTest is OrgFundFactoryTest {
    function testFuzz_DeployOrg(bytes32 _orgId, bytes32 _salt) public {
        address _expectedContractAddress = orgFundFactory.computeOrgAddress(_orgId, _salt);
        Org _org = orgFundFactory.deployOrg(_orgId, _salt);
        assertEq(_org.orgId(), _orgId);
        assertEq(globalTestRegistry, _org.registry());
        assertEq(_org.entityType(), 1);
        assertEq(_org.manager(), address(0));
        assertEq(_expectedContractAddress, address(_org));
    }

    function testFuzz_DeployOrgFailDuplicate(bytes32 _orgId, bytes32 _salt) public {
        orgFundFactory.deployOrg(_orgId, _salt);
        vm.expectRevert();
        orgFundFactory.deployOrg(_orgId, _salt);
    }

    function testFuzz_DeployOrgFailNonWhiteListedFactory(bytes32 _orgId, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory2.deployOrg(_orgId, _salt);
    }

    function testFuzz_DeployOrgFailAfterUnwhitelisting(bytes32 _orgId, bytes32 _salt) public {
        vm.assume(_orgId != "1234");
        orgFundFactory.deployOrg(_orgId, _salt);
        vm.prank(admin);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), false);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory.deployOrg("1234", _salt);
    }

    function testFuzz_DeployOrgFromFactory2(bytes32 _orgId, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.prank(admin);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory2), true);
        address _expectedContractAddress = orgFundFactory2.computeOrgAddress(_orgId, _salt);
        Org _org = orgFundFactory2.deployOrg(_orgId, _salt);
        assertEq(_org.orgId(), _orgId);
        assertEq(globalTestRegistry, _org.registry());
        assertEq(_org.entityType(), 1);
        assertEq(_expectedContractAddress, address(_org));
    }
}

contract OrgFundFactoryDeployFundTest is OrgFundFactoryTest {
    function testFuzz_DeployFund(address _manager, bytes32 _salt) public {
        address _expectedContractAddress = orgFundFactory.computeFundAddress(_manager, _salt);
        Fund _fund = orgFundFactory.deployFund(_manager, _salt);
        assertEq(globalTestRegistry, _fund.registry());
        assertEq(_fund.entityType(), 2);
        assertEq(_fund.manager(), _manager);
        assertEq(_expectedContractAddress, address(_fund));
    }

    function testFuzz_DeployFundDuplicateFail(address _manager, bytes32 _salt) public {
        orgFundFactory.deployFund(_manager, _salt);
        vm.expectRevert();
        orgFundFactory.deployFund(_manager, _salt);
    }

    function testFuzz_DeployFundFailNonWhiteListedFactory(address _manager, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory2.deployFund(_manager, _salt);
    }

    function testFuzz_DeployFundFailAfterUnwhitelisting(address _manager, bytes32 _salt) public {
        vm.assume(_manager != address(1234));
        orgFundFactory.deployFund(_manager, _salt);
        vm.prank(admin);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), false);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory.deployFund(address(1234), _salt);
    }

    function testFuzz_DeployFundFromFactory2(address _manager, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.prank(admin);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory2), true);
        address _expectedContractAddress = orgFundFactory2.computeFundAddress(_manager, _salt);
        Fund _fund = orgFundFactory2.deployFund(_manager, _salt);
        assertEq(globalTestRegistry, _fund.registry());
        assertEq(_fund.entityType(), 2);
        assertEq(_expectedContractAddress, address(_fund));
    }
}

