// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "./utils/DeployTest.sol";

import {OrgFundFactory} from "../OrgFundFactory.sol";
import {BatchOrgDeployer} from "../BatchOrgDeployer.sol";

contract BatchOrgDeployerTest is DeployTest {
    event EntityBatchDeployed(address indexed caller, uint8 indexed entityType, uint256 batchSize);

    BatchOrgDeployer batchOrgDeployer;

    function setUp() public override {
        super.setUp();
        batchOrgDeployer = new BatchOrgDeployer(orgFundFactory);
    }
}

contract BatchOrgDeployerConstructor is BatchOrgDeployerTest {
    function test_BatchOrgDeployerConstructor() public {
        assertEq(address(batchOrgDeployer.orgFundFactory()), address(orgFundFactory));
    }
}

contract BatchOrgDeployerOrgDeployTest is BatchOrgDeployerTest {
    uint256 constant ORG_AMOUNT = 25;

    mapping(bytes32 => address) public orgAddresses;

    function test_BatchOrgDeployerDeployOrgs() public {
        vm.expectEmit(true, true, false, true);
        emit EntityBatchDeployed(address(this), 1, ORG_AMOUNT);

        bytes32[] memory _orgIds = new bytes32[](ORG_AMOUNT);
        address[] memory _orgAddresses = new address[](ORG_AMOUNT);
        for (uint256 i = 0; i < ORG_AMOUNT; i++) {
            _orgIds[i] = bytes32(uint256(ORG_AMOUNT - i));
            _orgAddresses[i] = orgFundFactory.computeOrgAddress(_orgIds[i]);
        }

        // Deploy all orgs
        batchOrgDeployer.batchDeploy(_orgIds);

        for (uint256 i = 0; i < ORG_AMOUNT; i++) {
            assertEq(Org(payable(_orgAddresses[i])).orgId(), _orgIds[i]);
        }
    }
}
