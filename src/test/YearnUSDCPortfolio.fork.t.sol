// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";
import { IYVault } from "../interfaces/IYVault.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { YearnUSDCPortfolio } from "../portfolios/YearnUSDCPortfolio.sol";

contract YearnUSDCPortfolioTest is DeployTest {
    YearnUSDCPortfolio portfolio;
    Fund fund;

    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IYVault yvUsdc = IYVault(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE);
    address manager = user1;
    uint256 fundBalance = 1e27;

    // Price per share at block 14500000
    uint256 pricePerShare = 1013289;

    function setUp() public override virtual {
      super.setUp();

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
      portfolio = new YearnUSDCPortfolio(globalTestRegistry, address(usdc), type(uint256).max, 0);
      vm.prank(board);
      globalTestRegistry.setPortfolioStatus(portfolio, true);
    }
}

contract YUPConstructor is YearnUSDCPortfolioTest {
  function testFuzz_Constructor(uint256 _cap, uint256 _redemptionFee) public {
    _redemptionFee = bound(_redemptionFee, 0, Math.ZOC);
    YearnUSDCPortfolio _portfolio = new YearnUSDCPortfolio(globalTestRegistry, address(usdc), _cap, _redemptionFee);

    assertEq(_portfolio.name(), "Yearn USDC Vault Portfolio Shares");
    assertEq(_portfolio.symbol(), "yvUSDC-PS");
    assertEq(_portfolio.decimals(), usdc.decimals());
    assertEq(_portfolio.asset(), address(usdc));
    assertEq(_portfolio.cap(), _cap);
    assertEq(_portfolio.redemptionFee(), _redemptionFee);
    assertEq(_portfolio.totalAssets(), 0);
    assertEq(_portfolio.convertToAssets(1e6), 1e6); // Starts at 1:1
  }
}

contract YUPConversions is YearnUSDCPortfolioTest {
  using stdStorage for StdStorage;

  address opyn = 0x5934807cC0654d46755eBd2848840b616256C6Ef; // Opyn margin pool has lots of yvUSDC.

  function test_InitialExchangeRates() public {
    assertEq(yvUsdc.pricePerShare(), pricePerShare);
  }

  function test_SharesConversion() public {
    // Setup.
    address alice = address(0xaffab1e);
    stdstore.target(address(globalTestRegistry)).sig("isActiveEntity(address)").with_key(alice).checked_write(true);
    deal(address(usdc), alice, 1000e6);

    vm.prank(alice);
    usdc.approve(address(portfolio), type(uint256).max);

    // Estimate shares received.
    uint256 _sharesExpected = portfolio.convertToShares(1000e6);

    // Deposit and assert our estimation was correct.
    vm.prank(alice);
    uint256 _sharesActual = portfolio.deposit(1000e6, hex"");
    assertEq(_sharesActual, _sharesExpected);
  }

  function test_ConvertToUsdc() public {
    assertEq(portfolio.convertToUsdc(yvUsdc.balanceOf(opyn)), yvUsdc.pricePerShare() * yvUsdc.balanceOf(opyn) / 1e6);
  }
}

contract YUPIntegrationTest is YearnUSDCPortfolioTest {
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
    return portfolio.deposit(_usdcAmount, hex"");
  }

  function redeem(address _who) public returns (uint256) {
    uint256 _shares = portfolio.balanceOf(_who);
    vm.prank(_who);
    return portfolio.redeem(_shares, hex"");
  }

  function test_Integration() public {
    // TODO The hardcoded assertion tolerances are based on results, and feel a little bigger than I'd like...

    // 1. Alice deposits 30M, exchange rate should be 1:1
    uint256 _aliceShares = deposit(alice, 30e6);
    assertEq(_aliceShares, 30e6);
    assertEq(portfolio.balanceOf(alice), _aliceShares);
    // 6 decimals results in a decent amount of rounding error
    assertApproxEqAbs(portfolio.convertToAssets(portfolio.balanceOf(alice)), 30e6, 30);
    assertApproxEqAbs(portfolio.convertToShares(30e6), portfolio.balanceOf(alice), 30);
    assertEq(portfolio.totalSupply(), _aliceShares);
    assertApproxEqAbs(portfolio.totalAssets(), _aliceShares, 30);

    // 2. Endaoment takes 5M fees, Alice now can redeem 25M
    vm.prank(board);
    portfolio.takeFees(5e6);

    assertApproxEqAbs(portfolio.convertToAssets(portfolio.balanceOf(alice)), 25e6, 30);
    assertApproxEqAbs(portfolio.totalAssets(), 25e6, 30);
    assertEq(portfolio.totalSupply(), _aliceShares);

    // 3. Bob deposits 60M, Alice position remains unchanged
    uint256 _bobShares = deposit(bob, 60e6);

    // Same assertions about Alice's position
    assertEq(_aliceShares, 30e6);
    assertEq(portfolio.balanceOf(alice), _aliceShares);
    assertApproxEqAbs(portfolio.convertToAssets(portfolio.balanceOf(alice)), 25e6, 90);
    assertApproxEqAbs(portfolio.totalAssets(), 85e6, 90);
    assertEq(portfolio.totalSupply(), _aliceShares + _bobShares); // 102M shares

    // New assertions about Bob's position
    assertEq(portfolio.balanceOf(bob), _bobShares);
    assertApproxEqAbs(portfolio.convertToAssets(portfolio.balanceOf(bob)), 60e6, 43);

    // 4. Increase Yearn's cash (i.e. USDC balance) to simulate returns.
    deal(address(usdc), address(yvUsdc), usdc.balanceOf(address(yvUsdc)) * 2);
    assertGt(yvUsdc.pricePerShare(), pricePerShare);

    // 5. Alice and Bob should should get proportional amounts of USDC.
    // Zero out their balances to simplify the math.
    deal(address(usdc), alice, 0);
    deal(address(usdc), bob, 0);

    uint256 _aliceExpected = portfolio.totalAssets() * _aliceShares / portfolio.totalSupply();
    uint256 _bobExpected = portfolio.totalAssets() * _bobShares / portfolio.totalSupply();

    uint256 _aliceNet = redeem(alice);
    uint256 _bobNet = redeem(bob);

    assertApproxEqAbs(_aliceNet, _aliceExpected, 18);
    assertApproxEqAbs(_bobNet, _bobExpected, 45);
    assertLe(usdc.balanceOf(address(portfolio)), 4);
  }
}