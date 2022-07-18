// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import {MockSwapperTestHarness} from "./utils/MockSwapperTestHarness.sol";
import {Registry} from "../Registry.sol";
import {Math} from "../lib/Math.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Portfolio} from "../Portfolio.sol";
import {Fund} from "../Fund.sol";
import {SingleTokenPortfolio} from "../portfolios/SingleTokenPortfolio.sol";
import "forge-std/Test.sol";

error PortfolioInactive();
error DepositAfterShutdown();

contract SingleTokenPortfolioTest is MockSwapperTestHarness {
    using SafeTransferLib for ERC20;

    address entity;
    address manager = user1;
    Fund fund;
    SingleTokenPortfolio portfolio;
    uint256 fundBalance = 1e27;

    event CapSet(uint256 cap);
    event DepositFeeSet(uint256 fee);
    event RedemptionFeeSet(uint256 fee);
    event Deposit(
        address indexed sender,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 depositAmount,
        uint256 fee
    );
    event Redeem(
        address indexed sender,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 redeemedAmount,
        uint256 fee
    );
    event Shutdown(uint256 amountAsset, uint256 amountBaseToken);

    // Shadows EndaomentAuth
    error Unauthorized();

    function setUp() public virtual override {
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
        portfolio =
        new SingleTokenPortfolio(globalTestRegistry, address(testToken1), "Portfolio Share", "TPS", type(uint256).max, 0, 0);
        vm.prank(board);
        globalTestRegistry.setPortfolioStatus(portfolio, true);
    }
}

contract STPConstructor is SingleTokenPortfolioTest {
    function testFuzz_Constructor(
        string memory _name,
        string memory _symbol,
        uint256 _cap,
        uint256 _depositFee,
        uint256 _redemptionFee
    ) public {
        _redemptionFee = bound(_redemptionFee, 0, Math.ZOC);
        SingleTokenPortfolio _portfolio =
        new SingleTokenPortfolio(globalTestRegistry, address(testToken1), _name, _symbol, _cap, _depositFee, _redemptionFee);
        assertEq(_name, _portfolio.name());
        assertEq(_symbol, _portfolio.symbol());
        assertEq(_portfolio.decimals(), testToken1.decimals());
        assertEq(address(testToken1), _portfolio.asset());
        assertEq(_cap, _portfolio.cap());
        assertEq(_depositFee, _portfolio.depositFee());
        assertEq(_redemptionFee, _portfolio.redemptionFee());
        assertEq(0, _portfolio.totalAssets());
    }
}

contract STPSetCap is SingleTokenPortfolioTest {
    address[] actors = [board, investmentCommittee];

    function testFuzz_SetCap(uint256 _actor, uint256 _cap) public {
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

contract STPSetDepositFee is SingleTokenPortfolioTest {
    address[] actors = [board];

    function testFuzz_SetDepositFee(uint256 _actor, uint256 _fee) public {
        _actor = bound(_actor, 0, actors.length - 1);
        _fee = bound(_fee, 0, Math.ZOC);
        vm.expectEmit(false, false, false, true);
        emit DepositFeeSet(_fee);
        vm.prank(actors[_actor]);
        portfolio.setDepositFee(_fee);
        assertEq(_fee, portfolio.depositFee());
    }

    function testFuzz_SetDepositFeeFailAuth(uint256 _fee) public {
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        portfolio.setDepositFee(_fee);
    }

    function testFuzz_SetDepositFeeFailOver100(uint256 _fee) public {
        _fee = bound(_fee, Math.ZOC + 1, type(uint256).max);
        vm.prank(board);
        vm.expectRevert(Portfolio.PercentageOver100.selector);
        portfolio.setDepositFee(_fee);
    }
}

contract STPSetRedemptionFee is SingleTokenPortfolioTest {
    address[] actors = [board, programCommittee];

    function testFuzz_SetRedemptionFee(uint256 _actor, uint256 _fee) public {
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

    function testFuzz_convertToShares(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint120).max);
        uint256 _shares = portfolio.convertToShares(_amount);
        uint256 _assets = portfolio.convertToAssets(_shares);
        assertApproxEqAbs(_assets, _amount, 1e18);
    }

    function testFuzz_convertToAssets(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint120).max);
        uint256 _assets = portfolio.convertToAssets(_amount);
        uint256 _shares = portfolio.convertToShares(_assets);
        assertApproxEqAbs(_shares, _amount, 1e18);
    }
}

contract STPDeposit is SingleTokenPortfolioTest {
    address[] actors = [manager, board, investmentCommittee];

    function testFuzz_DepositSuccess(uint256 _amount, uint256 _depositFee, uint256 _actor) public {
        address actor = actors[_actor % actors.length];
        _depositFee = bound(_depositFee, 0, Math.ZOC);
        vm.prank(board);
        portfolio.setDepositFee(_depositFee); // fuzzing deposit fee inconsequential
        _amount = bound(_amount, 1, 1e7 ether);
        uint256 _amountFee = Math.zocmul(_amount, _depositFee);
        bytes memory _data = abi.encodePacked(address(mockSwapWrapper), bytes(""));
        uint256 _expectedAssets = mockSwapWrapper.amountOut();
        uint256 _expectedShares = portfolio.convertToShares(_expectedAssets);
        vm.expectEmit(true, true, false, true);
        emit Deposit(address(fund), address(fund), _expectedAssets, _expectedShares, _amount, _amountFee);
        vm.prank(actor);
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

    function testFuzz_DepositFailNotActivePortfolio(address _notPortfolio, uint256 _amount) public {
        vm.assume(_notPortfolio != address(portfolio));
        vm.expectRevert(PortfolioInactive.selector);
        vm.prank(manager);
        fund.portfolioDeposit(Portfolio(_notPortfolio), _amount, "");
    }

    function testFuzz_DepositFailDidShutdown(uint256 _amount) public {
        _amount = bound(_amount, 1, 1e7 ether);
        bytes memory _data = abi.encodePacked(address(mockSwapWrapper), bytes(""));

        // shutdown
        vm.prank(board);
        portfolio.shutdown(_data);

        // try to deposit
        vm.prank(manager);
        vm.expectRevert(DepositAfterShutdown.selector);
        fund.portfolioDeposit(portfolio, _amount, _data);
    }
}

contract STPDepositRedeem is SingleTokenPortfolioTest {
    address[] actors = [manager, board, investmentCommittee];

    //
    function testFuzz_DepositRedeemFeeSuccess(
        uint256 _amountSwapDeposit,
        uint256 _amountSwapRedemption,
        uint256 _redemptionFee,
        uint8 _actor
    ) public {
        // setup
        address actor = actors[_actor % actors.length];
        _amountSwapDeposit = bound(_amountSwapDeposit, 10000, 1e18 ether);
        _amountSwapRedemption = bound(_amountSwapRedemption, 10000, 1e18 ether);
        _redemptionFee = bound(_redemptionFee, 0, Math.ZOC);

        // set redemption fee
        vm.prank(board);
        portfolio.setRedemptionFee(_redemptionFee);

        // deposit
        uint256 _amountIn = 5; // arbitrary baseTokenIn that will be swapped for _amountSwapDeposit
        bytes memory _data = abi.encodePacked(address(mockSwapWrapper), bytes(""));
        mockSwapWrapper.setAmountOut(_amountSwapDeposit);
        vm.prank(manager);
        uint256 _shares = fund.portfolioDeposit(portfolio, _amountIn, _data);

        // redeem
        mockSwapWrapper.setAmountOut(_amountSwapRedemption);
        vm.prank(actor);
        uint256 _baseToken = fund.portfolioRedeem(portfolio, _shares, _data); // full redemption
        uint256 _expectedBaseTokenOut = _amountSwapRedemption - Math.zocmul(_amountSwapRedemption, _redemptionFee);
        assertEq(_baseToken, _expectedBaseTokenOut);
    }

    function testFuzz_DepositShutdownRedeemSuccess(
        uint256 _amountSwapDeposit,
        uint256 _amountSwapShutdown,
        uint256 _redemptionFee,
        uint8 _actor
    ) public {
        // setup
        address actor = actors[_actor % actors.length];
        _amountSwapDeposit = bound(_amountSwapDeposit, 10000, 1e18 ether);
        _amountSwapShutdown = bound(_amountSwapShutdown, 10000, 1e18 ether);
        _redemptionFee = bound(_redemptionFee, 0, Math.ZOC);

        // set redemption fee
        vm.prank(board);
        portfolio.setRedemptionFee(_redemptionFee);

        // deposit
        uint256 _amountIn = 5; // arbitrary baseTokenIn that will be swapped for _amountSwapDeposit
        bytes memory _data = abi.encodePacked(address(mockSwapWrapper), bytes(""));
        mockSwapWrapper.setAmountOut(_amountSwapDeposit);
        vm.prank(manager);
        uint256 _shares = fund.portfolioDeposit(portfolio, _amountIn, _data);

        // shutdown
        mockSwapWrapper.setAmountOut(_amountSwapShutdown);
        vm.prank(board);
        portfolio.shutdown(_data);

        // redeem
        vm.prank(actor);
        uint256 _baseToken = fund.portfolioRedeem(portfolio, _shares, _data); // full redemption
        uint256 _expectedBaseTokenOut = _amountSwapShutdown - Math.zocmul(_amountSwapShutdown, _redemptionFee);
        assertEq(_baseToken, _expectedBaseTokenOut);
    }
}

contract STPIntegrationTest is SingleTokenPortfolioTest {
    using stdStorage for StdStorage;

    address alice = address(0xaffab1e);
    address bob = address(0xbaff1ed);
    uint256 baseTokenOut = 12345654321;

    function setUp() public override {
        super.setUp();
        deal(address(baseToken), alice, 100e6);
        deal(address(baseToken), bob, 100e6);

        vm.prank(alice);
        baseToken.approve(address(portfolio), type(uint256).max);

        vm.prank(bob);
        baseToken.approve(address(portfolio), type(uint256).max);

        stdstore.target(address(globalTestRegistry)).sig("isActiveEntity(address)").with_key(alice).checked_write(true);
        stdstore.target(address(globalTestRegistry)).sig("isActiveEntity(address)").with_key(bob).checked_write(true);
    }

    function deposit(address _who, uint256 _swapOut) public returns (uint256) {
        mockSwapWrapper.setAmountOut(_swapOut);
        vm.prank(_who);
        return portfolio.deposit(
            42,
            /**
             * meaningless baseToken
             */
            abi.encodePacked(address(mockSwapWrapper), bytes(""))
        );
    }

    function redeem(address _who, uint256 _shares) public returns (uint256) {
        // The amount of baseTokenOut received is almost entirely dependent on the swap. Since we're using a MockSwapWrapper,
        // any assertion about what an Entity receives from an STP is effectively a useless assertion about MockSwapWrapper,
        // with the exception of redemptionFee-related assertions which are covered in STPDepositRedeem.
        mockSwapWrapper.setAmountOut(baseTokenOut);
        /**
         * arbitrary number (see above comment)
         */
        vm.prank(_who);
        return portfolio.redeem(_shares, abi.encodePacked(address(mockSwapWrapper), bytes("")));
    }

    function test_Integration() public {
        // 1. Alice deposits 30e18, exchange rate 1:1
        uint256 _aliceShares = deposit(alice, 30e18);
        assertEq(_aliceShares, 30e18);
        assertEq(portfolio.balanceOf(alice), _aliceShares);
        assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 30e18);
        assertEq(portfolio.convertToShares(30e18), portfolio.balanceOf(alice));
        assertEq(portfolio.totalSupply(), _aliceShares);
        assertEq(portfolio.totalAssets(), _aliceShares);
        assertEq(testToken1.balanceOf(address(portfolio)), portfolio.totalAssets());

        // 2. Endaoment takes 5M fees, Alice now can redeem 25e18
        vm.prank(board);
        portfolio.takeFees(5e18);

        assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 25e18);
        assertEq(portfolio.totalAssets(), 25e18);
        assertEq(portfolio.totalSupply(), _aliceShares);
        assertEq(testToken1.balanceOf(address(portfolio)), portfolio.totalAssets());

        // 3. Bob deposits 60e18, Alice position remains unchanged
        uint256 _bobShares = deposit(bob, 60e18);

        // Same assertions about Alice's position
        assertEq(_aliceShares, 30e18);
        assertEq(portfolio.balanceOf(alice), _aliceShares);
        assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 25e18);
        assertEq(portfolio.totalAssets(), 85e18);
        assertEq(testToken1.balanceOf(address(portfolio)), portfolio.totalAssets());
        assertEq(portfolio.totalSupply(), _aliceShares + _bobShares); // 102M shares

        // New assertions about Bob's position
        assertEq(portfolio.balanceOf(bob), _bobShares);
        assertEq(portfolio.convertToAssets(portfolio.balanceOf(bob)), 60e18);

        uint256 _aliceExpected = portfolio.totalAssets() * _aliceShares / portfolio.totalSupply();
        uint256 _bobExpected = portfolio.totalAssets() * _bobShares / portfolio.totalSupply();

        assertEq(portfolio.balanceOf(alice), _aliceShares);
        assertEq(testToken1.balanceOf(address(portfolio)), portfolio.totalAssets());
        assertEq(portfolio.convertToAssets(portfolio.balanceOf(alice)), 25e18);

        vm.expectEmit(true, true, false, true);
        emit Redeem(alice, alice, _aliceExpected, _aliceShares, baseTokenOut, 0);
        uint256 _aliceNet = redeem(alice, portfolio.balanceOf(alice));

        vm.expectEmit(true, true, false, true);
        emit Redeem(bob, bob, _bobExpected, _bobShares, baseTokenOut, 0);
        uint256 _bobNet = redeem(bob, portfolio.balanceOf(bob));

        assertEq(_aliceNet, baseTokenOut);
        assertEq(_bobNet, baseTokenOut);
        assertEq(testToken1.balanceOf(address(portfolio)), 0);
    }
}

contract STPShutdownTest is SingleTokenPortfolioTest {
    function testFuzz_Shutdown(uint256 _amountSwapDeposit, uint256 _swapOut) public {
        _amountSwapDeposit = bound(_amountSwapDeposit, 10000, 1e18 ether);
        _swapOut = bound(_swapOut, 10000, 1e18 ether);
        bytes memory _data = abi.encodePacked(address(mockSwapWrapper), bytes(""));
        mockSwapWrapper.setAmountOut(_amountSwapDeposit);

        vm.prank(manager);
        fund.portfolioDeposit(portfolio, 5, /* meaningless as amt gets swapped */ _data);
        assertFalse(portfolio.didShutdown());

        // shutdown
        mockSwapWrapper.setAmountOut(_swapOut);
        vm.prank(board);
        vm.expectEmit(true, true, true, true);
        emit Shutdown(_amountSwapDeposit, _swapOut);
        portfolio.shutdown(_data);
        assertTrue(portfolio.didShutdown());
    }
}

contract STPCallAsPortfolioTest is SingleTokenPortfolioTest {
    error CallFailed(bytes response);

    error AlwaysReverts();

    function alwaysRevertsCustom() external pure {
        revert AlwaysReverts();
    }

    function alwaysRevertsString() external pure {
        revert("ALWAYS_REVERT");
    }

    function alwaysRevertsSilently() external pure {
        revert();
    }

    function testFuzz_CanCallAsPortfolio(address _receiver, uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint256).max);
        uint256 _initialBalance = baseToken.balanceOf(_receiver);

        baseToken.mint(address(portfolio), _amount);

        // Transfer tokens out via callAsPortfolio method
        bytes memory _data = abi.encodeCall(baseToken.transfer, (_receiver, _amount));
        vm.prank(board);
        bytes memory _returnData = portfolio.callAsPortfolio(address(baseToken), 0, _data);
        (bool _transferSuccess) = abi.decode(_returnData, (bool));

        assertTrue(_transferSuccess);
        assertEq(baseToken.balanceOf(_receiver) - _initialBalance, _amount);
    }

    function test_CallAsPortfolioForwardsRevertString() public {
        // Bytes precalculated for this revert string.
        bytes memory _expectedRevert = abi.encodeWithSelector(
            CallFailed.selector,
            hex"08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000"
            hex"000000000000000000000000000000000d414c574159535f52455645525400000000000000000000000000000000000000"
        );

        // Call a method that reverts and verify the data is forwarded.
        bytes memory _data = abi.encodeCall(this.alwaysRevertsString, ());
        vm.prank(board);
        vm.expectRevert(_expectedRevert);
        portfolio.callAsPortfolio(address(this), 0, _data);
    }

    function test_CallAsPortfolioForwardsCustomError() public {
        // Bytes precalculated for this custom error.
        bytes memory _expectedRevert = abi.encodeWithSelector(CallFailed.selector, hex"47e794ec");

        // Call a method that reverts and verify the data is forwarded.
        bytes memory _data = abi.encodeCall(this.alwaysRevertsCustom, ());
        vm.prank(board);
        vm.expectRevert(_expectedRevert);
        portfolio.callAsPortfolio(address(this), 0, _data);
    }

    function test_CallAsPortfolioForwardsSilentRevert() public {
        // A silent error has no additional bytes.
        bytes memory _expectedRevert = abi.encodeWithSelector(CallFailed.selector, "");

        // Call a method that reverts and no data is forwarded.
        bytes memory _data = abi.encodeCall(this.alwaysRevertsSilently, ());
        vm.prank(board);
        vm.expectRevert(_expectedRevert);
        portfolio.callAsPortfolio(address(this), 0, _data);
    }

    function testFuzz_CallAsPortfolioUnauthorized(address _notAdmin, address _receiver, uint256 _amount) public {
        vm.assume(_notAdmin != board);

        baseToken.mint(address(portfolio), _amount);

        // Attempt to transfer tokens out via callAsPortfolio method as the manager
        bytes memory _data = abi.encodeCall(baseToken.transfer, (_receiver, _amount));
        vm.prank(_notAdmin);
        vm.expectRevert(Unauthorized.selector);
        portfolio.callAsPortfolio(address(baseToken), 0, _data);
    }

    function testFuzz_CallAsPortfolioToSendETH(address payable _receiver, uint256 _amount) public {
        // ensure the fuzzer hasn't picked one of our contracts, which won't have a fallback
        vm.assume(address(_receiver).code.length == 0);

        // TODO: remove these receiver checks when forge fuzzer fixes are in for allowing the prevention pre-compiled addresses
        //       and not pre-setting built-in forge addresses to have MAX UINT balances.
        vm.assume(_receiver != msg.sender);
        vm.assume(_receiver != 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
        vm.assume(_receiver > address(0x9));

        uint256 _initialBalance = _receiver.balance;

        vm.deal(address(portfolio), _amount);

        // Use callAsPortfolio to send ETH to receiver
        vm.prank(board);
        portfolio.callAsPortfolio(_receiver, _amount, "");

        assertEq(address(_receiver).balance - _initialBalance, _amount);
    }

    function testFuzz_CallAsPortfolioToForwardETH(address _receiver, uint256 _amount) public {
        // ensure the fuzzer hasn't picked one of our contracts, which won't have a fallback
        vm.assume(address(_receiver).code.length == 0);

        // TODO: remove these receiver checks when forge fuzzer fixes are in for allowing the prevention pre-compiled addresses
        //       and not pre-setting built-in forge addresses to have MAX UINT balances.
        vm.assume(_receiver != msg.sender);
        vm.assume(_receiver != 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
        vm.assume(_receiver > address(0x9));

        uint256 _initialBalance = _receiver.balance;

        // Deploy an entity and give it an ETH balance
        vm.deal(board, _amount);

        // Use callAsPortfolio to send ETH to receiver
        vm.prank(board);
        portfolio.callAsPortfolio{value: _amount}(_receiver, _amount, "");

        assertEq(address(_receiver).balance - _initialBalance, _amount);
    }
}
