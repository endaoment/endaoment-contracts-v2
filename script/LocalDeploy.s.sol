// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { Registry } from "../src/Registry.sol";

import { Deploy } from "./Deploy.s.sol";

/**
 * @notice Local Deploy script - manages the deployment of the protocol contracts onto a local Ethereum node for test purposes.
 */
contract LocalDeploy is Deploy {

    // deployment configuration for local testing
    address constant board = address(0x1);
    address constant treasury = address(0xface);
    address constant capitalCommittee = address(0xccc);
    address constant programCommittee = address(0xddd);
    address constant investmentCommittee = address(0xeee);
    address constant tokenTrust = address(0x7ab1e);
    // used by RollingMerkleDistributor
    bytes32 initialRoot = "beef_cafe";
    uint256 initialPeriod = 60 days;

    // anvil address 0 is used for deploying address
    address constant deployer = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

    // Main-net USDC token address
    address constant baseTokenAddress = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    /**
    * @notice Performs the deployment of the protocol contracts and their configuration on a local Ethereum node for test purposes.
    */
    function run() public {
        deploy(deployer, baseTokenAddress, treasury, initialRoot, initialPeriod);
        setAllRoles(capitalCommittee, programCommittee, investmentCommittee, tokenTrust);
        setBoard(board);
    }
}

