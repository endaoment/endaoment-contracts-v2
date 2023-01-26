// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "solmate/tokens/ERC20.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Registry} from "../src/Registry.sol";
import {OrgFundFactory} from "../src/OrgFundFactory.sol";
import {RolesAndCapabilitiesControl} from "../src/RolesAndCapabilitiesControl.sol";
import {NDAO} from "../src/NDAO.sol";
import {NVT, INDAO} from "../src/NVT.sol";
import {RollingMerkleDistributor} from "../src/RollingMerkleDistributor.sol";
import {UniV3Wrapper} from "../src/swapWrappers/UniV3Wrapper.sol";
import {AutoRouterWrapper} from "../src/swapWrappers/AutoRouterWrapper.sol";
import {ISwapWrapper} from "../src/interfaces/ISwapWrapper.sol";

import "forge-std/Script.sol";

/**
 * @notice Deploy script - manages the deployment of the protocol contracts and their initial configuration.
 */
contract Deploy is Script, RolesAndCapabilitiesControl {
    uint8 public constant OrgType = 1;
    uint8 public constant FundType = 2;

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
    function deployCore(address _baseTokenAddress, address _treasury) public {
        baseToken = ERC20(_baseTokenAddress);

        vm.broadcast();
        registry = new Registry(msg.sender, _treasury, baseToken);
        deployedContracts.registry = registry;
        console2.log("registryContractAddress", address(registry));

        vm.broadcast();
        deployedContracts.orgFundFactory = new OrgFundFactory(registry);
        console2.log("orgFundFactoryContractAddress", address(deployedContracts.orgFundFactory));

        vm.broadcast();
        registry.setFactoryApproval(address(deployedContracts.orgFundFactory), true);
        console2.log("Factory approval performed for Org/Fund Factory");

        console2.log("Local core protocol deployment SUCCESS");
    }

    function _deployAutoRouterWrapper(address _uniSwapRouter02) private returns (ISwapWrapper) {
        vm.broadcast();
        return new AutoRouterWrapper("Uniswap AutoRouter Wrapper", _uniSwapRouter02);
    }

    function deployAutoRouterWrapper(address _uniSwapRouter02) public {
        ISwapWrapper wrapper = _deployAutoRouterWrapper(_uniSwapRouter02);

        vm.broadcast();
        registry.setSwapWrapperStatus(wrapper, true);
        console2.log("AutoRouter wrapper", address(wrapper));
    }

    function deployStandaloneAutoRouterWrapper(address _uniSwapRouter02) public {
        _deployAutoRouterWrapper(_uniSwapRouter02);
    }

    function deployUniV3Wrapper(address _uniV3SwapRouter) public {
        vm.broadcast();
        ISwapWrapper wrapper = new UniV3Wrapper("UniV3 SwapRouter Wrapper", _uniV3SwapRouter);

        vm.broadcast();
        registry.setSwapWrapperStatus(wrapper, true);
        console2.log("uniswapV3SwapWrapperContractAddress", address(wrapper));
    }

    function deployTokens(bytes32 _initialRoot, uint256 _initialPeriod) public {
        vm.broadcast();
        deployedContracts.ndao = new NDAO(registry);
        console2.log("ndaoContractAddress", address(deployedContracts.ndao));

        vm.broadcast();
        deployedContracts.nvt = new NVT(INDAO(address(deployedContracts.ndao)), registry);
        console2.log("nvtContractAddress", address(deployedContracts.nvt));

        vm.broadcast();
        deployedContracts.distributor =
        new RollingMerkleDistributor(IERC20(address(deployedContracts.ndao)), _initialRoot, _initialPeriod, registry);
        console2.log("merkleDistributorContractAddress", address(deployedContracts.distributor));

        vm.broadcast();
        deployedContracts.baseDistributor =
            new RollingMerkleDistributor(IERC20(address(baseToken)), _initialRoot, _initialPeriod, registry);
        console2.log("merkleBaseTokenDistributorContractAddress", address(deployedContracts.baseDistributor));
    }

    /**
     * @notice Setup the proper roles and capabilities for the capitalCommittee, programCommittee, investmentCommittee, and tokenTrust.
     */
    function setAllRoles(
        address _capitalCommittee,
        address _programCommittee,
        address _investmentCommittee,
        address _tokenTrust
    ) public {
        vm.startBroadcast();
        setRolesAndCapabilities(
            registry,
            _capitalCommittee,
            _programCommittee,
            _investmentCommittee,
            _tokenTrust,
            deployedContracts.ndao,
            deployedContracts.nvt,
            deployedContracts.distributor,
            deployedContracts.baseDistributor
        );
        vm.stopBroadcast();
    }

    /**
     * @notice Sets most roles and capabilties, but not those for anything token-related.
     */
    function setCoreRoles(
        address _capitalCommittee,
        address _programCommittee,
        address _investmentCommittee,
        address _tokenTrust
    ) public {
        vm.startBroadcast();
        setCoreRolesAndCapabilities(registry, _capitalCommittee, _programCommittee, _investmentCommittee, _tokenTrust);
        vm.stopBroadcast();
    }

    /**
     * @notice Sets the owner of the deployed registry, a final step, turning over control from the deployer to the board.
     */
    function setBoard(address _newRegistryOwner) public {
        vm.broadcast();
        registry.transferOwnership(_newRegistryOwner);
        console2.log("Registry owner is now proposed to be", _newRegistryOwner);
        console2.log("For that user to become registry owner, they must execute registry.claimOwnership()");
    }
}
