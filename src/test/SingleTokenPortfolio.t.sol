// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import { MockSwapperTestHarness } from "./utils/MockSwapperTestHarness.sol";
import { Registry } from "../Registry.sol";
import { Math } from "../lib/Math.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { console2 } from "forge-std/console2.sol";
import { Portfolio } from "../Portfolio.sol";
import { Fund } from "../Fund.sol";
import { SingleTokenPortfolio } from "../portfolios/SingleTokenPortfolio.sol";
import "forge-std/Test.sol";

contract SingleTokenPortfolioTest is MockSwapperTestHarness {
    using SafeTransferLib for ERC20;
    address entity;
    address manager = user1;
    Fund fund;
    SingleTokenPortfolio portfolio;
    uint256 fundBalance = 1e27;

    event CapSet(uint256 cap);
    event RedemptionFeeSet(uint256 fee);
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
    event Redemption(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    // Shadows EndaomentAuth
    error Unauthorized();

    function setUp() public override {
      super.setUp();

      // set donation fees to 0
      // although it would be easier to do this in DeployTest, it causes testFuzz_UnmappedDefaultDonationFee to fail
      vm.startPrank(board);
      globalTestRegistry.setDefaultDonationFee(FundType, 0);
      globalTestRegistry.setDefaultDonationFee(OrgType, 0);
      vm.stopPrank();

      // deploy a provisioned fund
      fund = orgFundFactory.deployFund(manager, "soy sauce");
      deal(address(baseToken), manager, fundBalance);
      vm.startPrank(manager);
      baseToken.approve(address(fund), fundBalance);
      fund.donate(fundBalance);
      vm.stopPrank();

      // deploy portfolio
      portfolio = new SingleTokenPortfolio(globalTestRegistry, address(testToken1), "Portfolio Share", "TPS", type(uint256).max, 0);
      vm.prank(board);
      globalTestRegistry.setPortfolioStatus(portfolio, true);
    }
}

contract STPConstructor is SingleTokenPortfolioTest {
  function testFuzz_Constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _cap, uint256 _redemptionFee) public {
    _redemptionFee = bound(_redemptionFee, 0, Math.ZOC);
    SingleTokenPortfolio _portfolio = new SingleTokenPortfolio(globalTestRegistry, address(testToken1), _name, _symbol, _cap, _redemptionFee);
    assertEq(_name, _portfolio.name());
    assertEq(_symbol, _portfolio.symbol());
    assertEq(_portfolio.decimals(), testToken1.decimals());
    assertEq(address(testToken1), _portfolio.asset());
    assertEq(_cap, _portfolio.cap());
    assertEq(_redemptionFee, _portfolio.redemptionFee());
    assertEq(Math.WAD, _portfolio.exchangeRate());
    assertEq(0, _portfolio.totalAssets());
  }
}

contract STPSetCap is SingleTokenPortfolioTest {
  address[] actors = [board];
  function testFuzz_SetCap(uint _actor, uint256 _cap) public {
    _actor = bound(_actor, 0, actors.length - 1);
    vm.expectEmit(false, false, false, true);
    emit CapSet(_cap);
    vm.prank(actors[_actor]);
    portfolio.setCap(_cap);
    assertEq(_cap, portfolio.cap());
  }

  function testFuzz_SetRedemptionFeeFailAuth(uint256 _cap) public {
    vm.prank(user1);
    vm.expectRevert(Unauthorized.selector);
    portfolio.setRedemptionFee(_cap);
  }
}

contract STPSetRedemptionFee is SingleTokenPortfolioTest {
  address[] actors = [board];
  function testFuzz_SetRedemptionFee(uint _actor, uint256 _fee) public {
    _actor = bound(_actor, 0, actors.length - 1);
    _fee = bound(_fee, 0, Math.ZOC);
    vm.expectEmit(false, false, false, true);
    emit RedemptionFeeSet(_fee);
    vm.prank(actors[_actor]);
    portfolio.setRedemptionFee(_fee);
    assertEq(_fee, portfolio.redemptionFee());
  }

  function testFuzz_SetRedemptionFeeFailAuth(uint256 _fee) public {
    vm.prank(user1);
    vm.expectRevert(Unauthorized.selector);
    portfolio.setRedemptionFee(_fee);
  }

  function testFuzz_SetRedemptionFeeFailOver100(uint256 _fee) public {
    _fee = bound(_fee, Math.ZOC + 1, type(uint256).max);
    vm.prank(board);
    vm.expectRevert(Portfolio.PercentageOver100.selector);
    portfolio.setRedemptionFee(_fee);
  }
}

contract STPExchangeRateConvertMath is SingleTokenPortfolioTest {
    using stdStorage for StdStorage;
    function _setExchangeRate(uint256 _exchangeRate) internal {
        stdstore
            .target(address(portfolio))
            .sig(portfolio.exchangeRate.selector)
            .checked_write(_exchangeRate);
    }

  function testFuzz_convertToShares(uint256 _exchangeRate, uint256 _amount) public {
    _exchangeRate = bound(_exchangeRate, Math.WAD / 1000, Math.WAD);
    _amount = bound(_amount, 1, type(uint120).max);
    _setExchangeRate(_exchangeRate);
    uint256 _shares = portfolio.convertToShares(_amount);
    uint256 _assets = portfolio.convertToAssets(_shares);
    assertApproxEqAbs(_assets, _amount, 1e18);
  }

  function testFuzz_convertToAssets(uint256 _exchangeRate, uint256 _amount) public {
    _exchangeRate = bound(_exchangeRate,  Math.WAD / 1000, Math.WAD);
    _amount = bound(_amount, 1, type(uint120).max);
    _setExchangeRate(_exchangeRate);
    uint256 _assets = portfolio.convertToAssets(_amount);
    uint256 _shares = portfolio.convertToShares(_assets);
    assertApproxEqAbs(_shares, _amount, 1e18);
  }
}

contract STPDeposit is SingleTokenPortfolioTest {
  function testFuzz_DepositSuccess(uint256 _amount) public {
    _amount = bound(_amount, 1, 1e7 ether);
    bytes memory _data = abi.encodePacked(address(mockSwapWrapper), bytes(""));
    uint256 _expectedAssets = mockSwapWrapper.amountOut();
    uint256 _expectedShares = portfolio.convertToShares(_expectedAssets);
    vm.expectEmit(true, true, false, true);
    emit Deposit(address(fund), address(fund), _expectedAssets, _expectedShares);
    vm.prank(manager);
    uint256 shares = fund.portfolioDeposit(portfolio, _amount, _data);
    assertEq(mockSwapWrapper.amountOut(), shares);
    assertEq(portfolio.balanceOf(address(fund)), shares);
    assertEq(portfolio.totalAssets(), _expectedAssets);
  }

  function testFuzz_DepositFailNotEntity(address _notEntity, uint256 _amount) public {
    vm.assume(_notEntity != address(fund));
    bytes memory _data = bytes("");
    vm.expectRevert(Portfolio.NotEntity.selector);
    vm.prank(_notEntity);
    portfolio.deposit(_amount, _data);
  }

  function testFuzz_DepositFailExceedsCap(uint256 _cap, uint256 _amountBaseToken, uint256 _amountAssets) public {
    _amountBaseToken = bound(_amountBaseToken, 100, 1e9 ether);
    _amountAssets = bound(_amountAssets, 100, 1e9 ether);
    _cap = bound(_cap, 1, 1e9 ether);
    vm.assume(Math.WAD * _cap < Math.WAD * _amountAssets * _amountBaseToken / _amountAssets);
    vm.prank(board);
    portfolio.setCap(_cap);
    mockSwapWrapper.setAmountOut(_amountAssets);
    bytes memory _data = abi.encodePacked(address(mockSwapWrapper), bytes("swap data"));
    vm.expectRevert(Portfolio.ExceedsCap.selector);
    vm.prank(manager);
    fund.portfolioDeposit(portfolio, _amountBaseToken, _data);
  }

  // testFuzz_DepositExchangeRateMath - should take fees a couple times and ensure that minted shares match amountOut / exchangeRate
  
}


// Redemption tests
// convertToAssets / convertToShares
// multiple deposits / redemptions from same user
// multiple deposits / redemptions from different users
