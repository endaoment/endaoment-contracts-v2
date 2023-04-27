// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "./utils/DeployTest.sol";
import "../Registry.sol";
import {IAToken, ILendingPool} from "../interfaces/IAave.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {AaveV3USDCPortfolio} from "../portfolios/AaveV3USDCPortfolio.sol";

error DepositAfterShutdown();
error SyncAfterShutdown();

contract AaveV3USDCPortfolioTest is DeployTest {
    AaveV3USDCPortfolio portfolio;
    Fund fund;

    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IAToken public constant ausdc = IAToken(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
    address manager = user1;
    uint256 fundBalance = 1e27;

    function setUp() public virtual override {
        uint256 mainnetForkBlock = 17130422;
        vm.createSelectFork(vm.rpcUrl("mainnet"), mainnetForkBlock);
        DeployTest.setUp();

        // Deploy new contracts with mainnet base token.
        globalTestRegistry = new Registry(board, treasury, usdc);
        orgFundFactory = new OrgFundFactory(globalTestRegistry);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), true);

        // set donation fees to 0
        // although it would be easier to do this in DeployTest, it causes testFuzz_UnmappedDefaultDonationFee to fail
        vm.startPrank(board);
        globalTestRegistry.setDefaultDonationFee(FundType, 0);
        globalTestRegistry.setDefaultDonationFee(OrgType, 0);
        vm.stopPrank();

        // deploy a provisioned fund
        fund = orgFundFactory.deployFund(manager, "soy sauce");
        deal(address(usdc), manager, fundBalance);
        vm.startPrank(manager);
        usdc.approve(address(fund), fundBalance);
        fund.donate(fundBalance);
        vm.stopPrank();

        // deploy portfolio
        portfolio = new AaveV3USDCPortfolio(globalTestRegistry, address(usdc), type(uint256).max, 0, 0);
        vm.prank(board);
        globalTestRegistry.setPortfolioStatus(portfolio, true);
    }
}

contract AUPV3Constructor is AaveV3USDCPortfolioTest {
    function testFuzz_Constructor(uint256 _cap, uint256 _depositFee, uint256 _redemptionFee) public {
        _redemptionFee = bound(_redemptionFee, 0, Math.ZOC);
        AaveV3USDCPortfolio _portfolio =
            new AaveV3USDCPortfolio(globalTestRegistry, address(usdc), _cap, _depositFee, _redemptionFee);

        assertEq(_portfolio.name(), "Aave V3 USDC Portfolio Shares");
        assertEq(_portfolio.symbol(), "aEthUSDC-PS");
        assertEq(_portfolio.decimals(), usdc.decimals());
        assertEq(_portfolio.asset(), address(usdc));
        assertEq(_portfolio.cap(), _cap);
        assertEq(_portfolio.depositFee(), _depositFee);
        assertEq(_portfolio.redemptionFee(), _redemptionFee);
        assertEq(_portfolio.totalAssets(), 0);
        assertEq(_portfolio.convertToAssets(1e6), 1e6); // Starts at 1:1
    }
}

contract AUPV3IntegrationTest is AaveV3USDCPortfolioTest {
    using stdStorage for StdStorage;

    address alice = address(0xaffab1e);
    address bob = address(0xbaff1ed);

    function setUp() public override {
        super.setUp();
        deal(address(usdc), alice, 100e6);
        deal(address(usdc), bob, 100e6);

        vm.prank(alice);
        usdc.approve(address(portfolio), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(portfolio), type(uint256).max);

        stdstore.target(address(globalTestRegistry)).sig("isActiveEntity(address)").with_key(alice).checked_write(true);
        stdstore.target(address(globalTestRegistry)).sig("isActiveEntity(address)").with_key(bob).checked_write(true);
    }

    function deposit(address _who, uint256 _usdcAmount) public returns (uint256) {
        vm.prank(_who);
        return portfolio.deposit(_usdcAmount, 0);
    }

    function redeem(address _who) public returns (uint256) {
        uint256 _shares = portfolio.balanceOf(_who);
        vm.prank(_who);
        return portfolio.redeem(_shares, 0);
    }

    function test_Integration() public {
        // 1. Alice deposits 30M, exchange rate should be 1:1
        uint256 _aliceShares = deposit(alice, 30e6);
        assertEq(_aliceShares, 30e6);
        assertEq(portfolio.balanceOf(alice), _aliceShares);
        assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 30e6);
        assertEq(portfolio.convertToShares(30e6), portfolio.balanceOf(alice));
        assertEq(portfolio.totalSupply(), _aliceShares);
        assertEq(portfolio.totalAssets(), _aliceShares);

        // 2. Endaoment takes 5M fees, Alice now can redeem 25M
        address _treasury = portfolio.registry().treasury();
        assertEq(usdc.balanceOf(_treasury), 0);
        vm.prank(board);
        portfolio.takeFees(5e6);
        assertEq(usdc.balanceOf(_treasury), 5e6);

        assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 25e6);
        assertEq(portfolio.totalAssets(), 25e6);
        assertEq(portfolio.totalSupply(), _aliceShares);

        // 3. Bob deposits 60M, Alice position remains unchanged
        uint256 _bobShares = deposit(bob, 60e6);

        // Same assertions about Alice's position
        assertEq(_aliceShares, 30e6);
        assertEq(portfolio.balanceOf(alice), _aliceShares);
        assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 25e6);
        assertEq(portfolio.totalAssets(), 85e6 + 1); // +1 due to rounding error.
        assertEq(portfolio.totalSupply(), _aliceShares + _bobShares);
        assertEq(portfolio.totalSupply(), 102e6);

        // New assertions about Bob's position
        assertEq(portfolio.balanceOf(bob), _bobShares);
        assertEq(portfolio.convertToAssets(portfolio.balanceOf(bob)), 60e6);

        // 4. Increase the Portfolio's aUSDC balance to simulate returns.
        // We do this by pranking from a mainnet aUSDC whale and transferring it to the portfolio, because aTokens
        // have a dynamic balanceOf method so `deal` doesn't work.
        uint256 _startBalance = portfolio.totalAssets();
        address whale = 0xD56353E0bDc41Ad232F9d11109868703c1e2b2B9; // Random whale with lots of Aave V3 aUSDC.
        vm.prank(whale);
        ausdc.transfer(address(portfolio), 100e6);
        assertGt(portfolio.totalAssets(), _startBalance);

        // 5. Alice and Bob should should get proportional amounts of USDC.
        // Zero out their balances to simplify the math.
        deal(address(usdc), alice, 0);
        deal(address(usdc), bob, 0);

        uint256 _aliceExpected = portfolio.totalAssets() * _aliceShares / portfolio.totalSupply();
        uint256 _bobExpected = portfolio.totalAssets() * _bobShares / portfolio.totalSupply();

        uint256 _aliceNet = redeem(alice);
        uint256 _bobNet = redeem(bob);

        assertEq(_aliceNet, _aliceExpected);
        assertEq(_bobNet, _bobExpected);
        assertEq(usdc.balanceOf(address(portfolio)), 0);
    }

    function test_RevertIf_DepositSlippageTooHigh() public {
        vm.prank(alice);
        vm.expectRevert(AaveV3USDCPortfolio.Slippage.selector);
        portfolio.deposit(30e6, 31e6);
    }

    function test_RevertIf_RedeemSlippageTooHigh() public {
        uint256 _shares = deposit(alice, 30e6);

        vm.prank(alice);
        vm.expectRevert(AaveV3USDCPortfolio.Slippage.selector);
        portfolio.redeem(_shares, 31e6);
    }

    function testFuzz_DepositFailDidShutdown(uint256 _amount) public {
        // deposit something into the portfolio, otherwise the the shutdown will fail on withdrawal
        deposit(alice, 30e6);

        _amount = bound(_amount, 1, 1e7 ether);
        bytes memory _data = hex"";

        // shutdown
        vm.prank(board);
        portfolio.shutdown(_data);

        // try to deposit
        vm.prank(manager);
        vm.expectRevert(DepositAfterShutdown.selector);
        fund.portfolioDeposit(portfolio, _amount, _data);
    }

    function test_SyncFailDidShutdown() public {
        // deposit something into the portfolio, otherwise the the shutdown will fail on withdrawal
        deposit(alice, 30e6);

        bytes memory _data = hex"";

        // shutdown
        vm.prank(board);
        portfolio.shutdown(_data);

        // try to sync
        vm.prank(board);
        vm.expectRevert(SyncAfterShutdown.selector);
        portfolio.sync();
    }
}
