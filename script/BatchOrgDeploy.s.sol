// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import {BatchOrgDeployer} from "../src/BatchOrgDeployer.sol";
import {Org} from "../src/Org.sol";
import {ScriptHelpers} from "./ScriptHelpers.s.sol";

/**
 * @notice BatchOrgDeploy script - manages the deployment of a batch of Orgs, using the `BatchOrgDeploy` contract
 */
contract BatchOrgDeploy is Script, ScriptHelpers {
    address constant BATCH_ORG_DEPLOYER_ADDRESS =
        0x5012CB8A192DB05260673a795B18aa5329D3D4c2;

    uint256 constant BATCH_SIZE = 25;

    string[] public orgsToDeploy;

    bytes32[] public currentBatch;

    /**
     * @notice Performs the deployment of a batch of Org entity contracts, given an input file of EINs
     * @dev The input file for now is simply a list of EINs, one per line.
     * @param _inputFile The file path to a file containing a list of Org ID / EIN values, one per line.
     * @dev The input file should have no blank lines, as that would erroneously indicate an end of the list.
     * @dev TODO: when forge scripting supports JSON parsing the input file can become a JSON array of EIN/Org Ids.
     */
    function batchDeployOrgs(string memory _inputFile) public {
        BatchOrgDeployer _batchOrgDeployer = BatchOrgDeployer(
            BATCH_ORG_DEPLOYER_ADDRESS
        );

        parseInputFile(_inputFile);

        for (uint256 i = 0; i < orgsToDeploy.length; i++) {
            bytes32 _ein = stringToBytes32(orgsToDeploy[i]);

            currentBatch.push(_ein);

            if (
                currentBatch.length == BATCH_SIZE ||
                i == orgsToDeploy.length - 1
            ) {
                vm.broadcast();
                _batchOrgDeployer.batchDeploy(currentBatch);
                delete currentBatch;
            }
        }
    }

    function parseInputFile(string memory _inputFilePath) private {
        while (true) {
            string memory _ein = vm.readLine(_inputFilePath);
            if (keccak256(bytes(_ein)) == keccak256(bytes(""))) break;
            orgsToDeploy.push(_ein);
        }
    }
}
