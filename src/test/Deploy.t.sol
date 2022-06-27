// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { Deploy } from "../../script/Deploy.s.sol";
import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { Fund } from "../Fund.sol";
import { Org } from "../Org.sol";

contract DeployTest is Deploy, DSTestPlus {

    address board = address(0x1);
    address treasury = address(0xface);
    
    // used by RollingMerkleDistributor
    bytes32 initialRoot = "beef_cafe";
    uint256 initialPeriod = 60 days;

    address capitalCommittee = address(0xccc);
    address programCommittee = address(0xddd);
    address investmentCommittee = address(0xeee);
    address tokenTrust = address(0x7ab1e);

    // deploying address
    address constant deployer = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

    // Main-net USDC token address
    address constant baseTokenAddress = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);


    function testDeployCoreProtocolWithFundAndOrg(address _manager, bytes32 _salt, bytes32 _orgId) public {
        deploy(deployer, baseTokenAddress, treasury, initialRoot, initialPeriod);
        setAllRoles(capitalCommittee, programCommittee, investmentCommittee, tokenTrust);
        setBoard(board);
        Fund _fund = deployedContracts.orgFundFactory.deployFund(_manager, _salt);
        assertEq(_fund.manager(), _manager);
        Org _org = deployedContracts.orgFundFactory.deployOrg(_orgId, _salt);
        assertEq(_org.orgId(), _orgId);
    }
}
