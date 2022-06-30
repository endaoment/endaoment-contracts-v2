// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import "solmate/tokens/ERC20.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { Registry } from "../src/Registry.sol";
import { OrgFundFactory} from "../src/OrgFundFactory.sol";
import { RolesAndCapabilitiesControl } from "../src/RolesAndCapabilitiesControl.sol";
import { NDAO } from "../src/NDAO.sol";
import { NVT, INDAO } from "../src/NVT.sol";
import { RollingMerkleDistributor } from "../src/RollingMerkleDistributor.sol";

import "forge-std/Script.sol";

/**
 * @notice Deploy script - manages the deployment of the protocol contracts and their initial configuration.
 */
contract Deploy is Script, RolesAndCapabilitiesControl {

    // Core protocol contract collection (returned from deploy)
    struct DeployedEndaomentInstance {
        Registry registry;
        OrgFundFactory orgFundFactory;
        NDAO ndao;
        NVT nvt;
        RollingMerkleDistributor distributor;
        RollingMerkleDistributor baseDistributor;
    }

    // Core protocol contracts
    DeployedEndaomentInstance deployedContracts;

    Registry registry;
    ERC20 baseToken;

    /**
     * @notice Performs the deployment of the core protocol contracts to an Ethereum network.
     */
    function deploy(address _deployer, address _baseTokenAddress, address _treasury, bytes32 _initialRoot, uint256 _initialPeriod) public {
        console2.log("deployerAddress", _deployer);
        baseToken = ERC20(_baseTokenAddress);

        // deploy core contracts
        vm.broadcast();
        registry = new Registry(_deployer, _treasury, baseToken);
        deployedContracts.registry = registry;
        console2.log("registryContractAddress", address(registry));

        vm.broadcast();
        deployedContracts.orgFundFactory = new OrgFundFactory(registry);
        console2.log("orgFundFactoryContractAddress", address(deployedContracts.orgFundFactory));

        vm.broadcast();
        registry.setFactoryApproval(address(deployedContracts.orgFundFactory), true);
        console2.log("Factory approval performed for Org/Fund Factory");

        vm.broadcast();
        deployedContracts.ndao = new NDAO(registry);
        console2.log("ndaoContractAddress", address(deployedContracts.ndao));

        vm.broadcast();
        deployedContracts.nvt = new NVT(INDAO(address(deployedContracts.ndao)), registry);
        console2.log("nvtContractAddress", address(deployedContracts.nvt));

        vm.broadcast();
        deployedContracts.distributor = new RollingMerkleDistributor(IERC20(address(deployedContracts.ndao)), _initialRoot, _initialPeriod, registry);
        console2.log("merkleDistributorContractAddress", address(deployedContracts.distributor));

        vm.broadcast();
        deployedContracts.baseDistributor = new RollingMerkleDistributor(IERC20(address(baseToken)), _initialRoot, _initialPeriod, registry);
        console2.log("merkleBaseTokenDistributorContractAddress", address(deployedContracts.baseDistributor));

        console2.log("Local core protocol deployment SUCCESS");
    }

    /**
     * @notice Setup the proper roles and capabilities for the capitalCommittee, programCommittee, investmentCommittee, and tokenTrust.
     */
    function setAllRoles(address _capitalCommittee, address _programCommittee, address _investmentCommittee, address _tokenTrust) public {
        vm.startBroadcast();
        setRolesAndCapabilities(registry, _capitalCommittee, _programCommittee, _investmentCommittee, _tokenTrust,
                                deployedContracts.ndao, deployedContracts.nvt, deployedContracts.distributor, deployedContracts.baseDistributor);

        vm.stopBroadcast();

        console2.log("Capital Committee: (2)", _capitalCommittee);
        console2.log("Program Committee: (3)", _programCommittee);
        console2.log("Investment Committee: (4)", _investmentCommittee);
        console2.log("Token Trust: (5)", _tokenTrust);
    }

    /**
     * @notice Sets the owner of the deployed registry, a final step, turning over control from the deployer to the board.
     */
    function setBoard(address _newRegistryOwner) public {
        vm.broadcast();
        registry.setOwner(_newRegistryOwner);
        console2.log("Registry owner: (0)" , _newRegistryOwner);
    }
}
