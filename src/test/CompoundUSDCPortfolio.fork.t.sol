// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";
import { ICErc20 } from "../interfaces/ICErc20.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { CompoundUSDCPortfolio } from "../portfolios/CompoundUSDCPortfolio.sol";

contract CompoundUSDCPortfolioTest is DeployTest {
    CompoundUSDCPortfolio portfolio;
    Fund fund;

    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ICErc20 cusdc = ICErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    address manager = user1;
    uint256 fundBalance = 1e27;

    // cUSDC exchange rates at block 14500000
    uint256 exchangeRateStored = 225506684689544;
    uint256 exchangeRateCurrent = 225506689445887;
  
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
      portfolio = new CompoundUSDCPortfolio(globalTestRegistry, address(usdc), type(uint256).max, 0);
      vm.prank(board);
      globalTestRegistry.setPortfolioStatus(portfolio, true);
    }
}

contract CUPConstructor is CompoundUSDCPortfolioTest {
  function testFuzz_Constructor(uint256 _cap, uint256 _redemptionFee) public {
    _redemptionFee = bound(_redemptionFee, 0, Math.ZOC);
    CompoundUSDCPortfolio _portfolio = new CompoundUSDCPortfolio(globalTestRegistry, address(usdc), _cap, _redemptionFee);

    assertEq(_portfolio.name(), "Compound USDC Portfolio Shares");
    assertEq(_portfolio.symbol(), "cUSDC-PS");
    assertEq(_portfolio.decimals(), usdc.decimals());
    assertEq(_portfolio.asset(), address(usdc));
    assertEq(_portfolio.cap(), _cap);
    assertEq(_portfolio.redemptionFee(), _redemptionFee);
    assertEq(_portfolio.totalAssets(), 0);
    assertEq(_portfolio.convertToAssets(1e6), 1e6); // Starts at 1:1
  }
}

contract CUPConversions is CompoundUSDCPortfolioTest {
  address justin = 0x3DdfA8eC3052539b6C9549F12cEA2C295cfF5296; // Justin Sun has a lot of cUSDC!

  function test_InitialExchangeRates() public {
    assertEq(cusdc.exchangeRateStored(), exchangeRateStored);
    assertEq(cusdc.exchangeRateCurrent(), exchangeRateCurrent);
  }

  function test_ComputeCurrentExchangeRate() public {
    assertEq(cusdc.exchangeRateStored(), exchangeRateStored); // Sanity check that stored != current.
    assertEq(portfolio.compoundExchangeRateCurrent(), cusdc.exchangeRateCurrent()); // Order of args matters here, we don't want to update Compound yet.
    assertEq(portfolio.compoundExchangeRateCurrent(), cusdc.exchangeRateCurrent()); // Check it again to make sure it's still accurate after updates.
    assertEq(cusdc.exchangeRateCurrent(), exchangeRateCurrent);
  }

  function test_ConvertToUsdc() public {
    assertEq(portfolio.convertToUsdc(cusdc.balanceOf(justin)), cusdc.balanceOfUnderlying(justin));
  }
}

contract CUPIntegrationTest is CompoundUSDCPortfolioTest {
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
    // 1. Alice deposits 30M, exchange rate should be 1:1
    uint256 _aliceShares = deposit(alice, 30e6);
    assertEq(_aliceShares, 30e6);
    assertEq(portfolio.balanceOf(alice), _aliceShares);
    assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 30e6 - 1); // Rounding error, down from 30M
    assertEq(portfolio.convertToShares(30e6), portfolio.balanceOf(alice) + 1); // Rounding error, up from 30M
    assertEq(portfolio.totalSupply(), _aliceShares);
    assertEq(portfolio.totalAssets(), _aliceShares - 1); // -1 again from rounding error

    // 2. Endaoment takes 5M fees, Alice now can redeem 25M
    vm.prank(board);
    portfolio.takeFees(5e6);

    assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 25e6);
    assertEq(portfolio.totalAssets(), 25e6);
    assertEq(portfolio.totalSupply(), _aliceShares);

    // 3. Bob deposits 60M, Alice position remains unchanged
    uint256 _bobShares = deposit(bob, 60e6);

    // Same assertions about Alice's position
    assertEq(_aliceShares, 30e6);
    assertEq(portfolio.balanceOf(alice), _aliceShares);
    assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 25e6);
    assertEq(portfolio.totalAssets(), 85e6);
    assertEq(portfolio.totalSupply(), _aliceShares + _bobShares); // 102M shares

    // New assertions about Bob's position
    assertEq(portfolio.balanceOf(bob), _bobShares);
    assertEq(portfolio.convertToAssets(portfolio.balanceOf(bob)), 60e6);

    // 4. Increase Compound's cash (i.e. USDC balance) to simulate returns.
    deal(address(usdc), address(cusdc), usdc.balanceOf(address(cusdc)) * 2);
    assertGt(cusdc.exchangeRateStored(), exchangeRateStored);

    // 5. Alice and Bob should should get proportional amounts of USDC.
    // Zero out their balances to simplify the math.
    deal(address(usdc), alice, 0);
    deal(address(usdc), bob, 0);
  
    uint256 _aliceExpected = portfolio.totalAssets() * _aliceShares / portfolio.totalSupply();
    uint256 _bobExpected = portfolio.totalAssets() * _bobShares / portfolio.totalSupply();

    uint256 _aliceNet = redeem(alice);
    uint256 _bobNet = redeem(bob);

    assertEq(_aliceNet, _aliceExpected);
    assertEq(_bobNet, _bobExpected + 1); // +1 to account for rounding error
    assertEq(usdc.balanceOf(address(portfolio)), 0);
  }
}