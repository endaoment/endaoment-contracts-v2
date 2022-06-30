// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { Registry } from "../src/Registry.sol";

import { Deploy } from "./Deploy.s.sol";
import "forge-std/Script.sol";

/**
 * @notice Local Deploy script - manages the deployment of the protocol contracts onto a local Ethereum node for test purposes.
 */
contract LocalDeploy is Deploy {

    // deployment configuration for local testing
    address constant board = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);                   // Anvil Address 0
    address constant treasury = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);                // Anvil Address 1
    address constant capitalCommittee = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);        // Anvil Address 2
    address constant programCommittee = address(0x90F79bf6EB2c4f870365E785982E1f101E93b906);        // Anvil Address 3
    address constant investmentCommittee = address(0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65);     // Anvil Address 4
    address constant tokenTrust = address(0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc);              // Anvil Address 5

    // used by RollingMerkleDistributor
    bytes32 initialRoot = "beef_cafe";
    uint256 initialPeriod = 60 days;

    // Board is used as the deployer
    address constant deployer = board;

    // Main-net USDC token address
    address constant baseTokenAddress = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    /**
    * @notice Performs the deployment of the protocol contracts and their configuration on a local Ethereum node for test purposes.
    */
    function run() public {
        deploy(deployer, baseTokenAddress, treasury, initialRoot, initialPeriod);

        console2.log(""); // new line for the roles
        console2.log("======= ROLES =======");
        console2.log("Treasury: (1)", treasury);
        setAllRoles(capitalCommittee, programCommittee, investmentCommittee, tokenTrust);
        setBoard(board);
        console2.log("======= ROLES =======");
    }
}

