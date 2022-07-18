// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import {Registry} from "../src/Registry.sol";

import {Deploy} from "./Deploy.s.sol";
import {SingleTokenPortfolio} from "../src/portfolios/SingleTokenPortfolio.sol";
import {CompoundUSDCPortfolio} from "../src/portfolios/CompoundUSDCPortfolio.sol";
import {AaveUSDCPortfolio} from "../src/portfolios/AaveUSDCPortfolio.sol";
import {YearnUSDCPortfolio} from "../src/portfolios/YearnUSDCPortfolio.sol";
import "forge-std/Script.sol";

/**
 * @notice Local Deploy script - manages the deployment of the protocol contracts onto a local Ethereum node for test purposes.
 */
contract LocalDeploy is Deploy {
    // deployment configuration for local testing
    address constant board = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266); // Anvil Address 0
    address constant treasury = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8); // Anvil Address 1
    address constant capitalCommittee = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC); // Anvil Address 2
    address constant programCommittee = address(0x90F79bf6EB2c4f870365E785982E1f101E93b906); // Anvil Address 3
    address constant investmentCommittee = address(0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65); // Anvil Address 4
    address constant tokenTrust = address(0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc); // Anvil Address 5

    // used by RollingMerkleDistributor
    bytes32 initialRoot = "beef_cafe";
    uint256 initialPeriod = 60 days;

    // Board is used as the deployer
    address constant deployer = board;

    // Mainnet USDC token address
    address constant baseTokenAddress = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // Mainnet Uniswap V3 Swap Router
    address constant uniV3SwapRouter = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // Mainnet Uniswap Swap router for use in AutoRouter
    address constant uniSwapRouter02 = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    // Main-net WETH Contract
    address constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /**
     * @notice Performs the deployment of the protocol contracts and their configuration on a local Ethereum node for test purposes.
     */
    function run() public {
        deployCore(baseTokenAddress, treasury);
        deployUniV3Wrapper(uniV3SwapRouter);
        deployAutoRouterWrapper(uniSwapRouter02);
        deployTokens(initialRoot, initialPeriod);

        vm.broadcast();
        registry.setDefaultDonationFee(OrgType, 50); // 0.5% donation fee to orgs

        vm.broadcast();
        registry.setDefaultDonationFee(FundType, 50); // 0.5% donation fee to funds

        // No fee for payout
        vm.broadcast();
        registry.setDefaultPayoutFee(OrgType, 0);

        vm.broadcast();
        registry.setDefaultPayoutFee(FundType, 0);

        // Granting 1.0% fees are applied for transfers from Fund to Orgs
        vm.broadcast();
        registry.setDefaultTransferFee(FundType, OrgType, 100);

        // Org to Fund transfers have a 0.5% fees
        vm.broadcast();
        registry.setDefaultTransferFee(OrgType, FundType, 50);

        // No transfer fees for remaining entity to entity transfers
        vm.broadcast();
        registry.setDefaultTransferFee(OrgType, OrgType, 0);
        vm.broadcast();
        registry.setDefaultTransferFee(FundType, FundType, 0);

        console2.log(""); // new line for the roles
        console2.log("======= ROLES =======");
        console2.log("Treasury: (1)", treasury);
        setAllRoles(capitalCommittee, programCommittee, investmentCommittee, tokenTrust);
        setBoard(board);
        console2.log("======= ROLES =======");

        deployPortfolios();
    }

    function deployPortfolios() public {
        uint256 depositFee = 50; // 0.5% Deposit Fee
        uint256 redemptionFee = 100; // 1% Redeption Fee

        console2.log(""); // new line for the Portfolios
        console2.log("======= PORTFOLIOS =======");

        // Creates and registers a WETH Portfolio in the registry, with a 15 Million Dollars Cap
        vm.broadcast();
        SingleTokenPortfolio stp =
        new SingleTokenPortfolio(registry, weth, "ETH Portfolio Shares", "ETH-PS", 15_000_000_000_000, depositFee, redemptionFee);
        console2.log("ETH Single Token Portfolio: ", address(stp));

        vm.broadcast();
        registry.setPortfolioStatus(stp, true);

        // Creates and registers a Coumpound Yield Bearing Portfolio in the registry, with no cap and no fees
        vm.broadcast();
        CompoundUSDCPortfolio compound =
            new CompoundUSDCPortfolio(registry, address(baseTokenAddress), type(uint256).max, 0, 0);
        console2.log("Compound Yield Portfolio: ", address(compound));

        vm.broadcast();
        registry.setPortfolioStatus(compound, true);

        // Creates and registers an AAVE Yield Bearing Portfolio in the registry, with no cap and no fees
        vm.broadcast();
        AaveUSDCPortfolio aave = new AaveUSDCPortfolio(registry, address(baseTokenAddress), type(uint256).max, 0, 0);
        console2.log("Aave Yield Portfolio: ", address(aave));

        vm.broadcast();
        registry.setPortfolioStatus(aave, true);

        // Creates and registers an Yearn Yield Bearing Portfolio in the registry, with no cap and no fees
        vm.broadcast();
        YearnUSDCPortfolio yearn = new YearnUSDCPortfolio(registry, address(baseTokenAddress), type(uint256).max, 0, 0);
        console2.log("Yearn Yield Portfolio: ", address(yearn));

        vm.broadcast();
        registry.setPortfolioStatus(yearn, true);

        // Creates a Portfolio, but never register it at the registry. DO NOT COPY THIS PORTFOLIO TO PRODUCTION
        vm.broadcast();
        SingleTokenPortfolio roguePortfolio =
        new SingleTokenPortfolio(registry, baseTokenAddress, "USDC Portfolio Shares", "USDC-PS", type(uint256).max, depositFee, redemptionFee);
        console2.log("Rogue Portfolio: ", address(roguePortfolio));

        console2.log("======= PORTFOLIOS =======");
    }
}
