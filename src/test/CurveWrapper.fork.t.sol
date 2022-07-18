// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "./utils/DeployTest.sol";
import "../Registry.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {console2} from "forge-std/console2.sol";
import {CurveWrapper} from "../swapWrappers/CurveWrapper.sol";
import {ICurveExchange} from "../interfaces/ICurveExchange.sol";
import {IWETH9} from "../lib/IWETH9.sol";

abstract contract CurveWrapperTest is DeployTest {
    using SafeTransferLib for ERC20;

    address curvePool;
    address tokenA;
    address tokenB;
    uint256 amountOutExpectedA;
    uint256 amountOutExpectedB;

    // switch flag to true to see amountOuts
    bool logAmountOut = false;

    address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address steth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address sender = user1;
    address receiver = user2;
    uint256 amount = 1e22;

    event WrapperSwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        address sender,
        address indexed recipient,
        uint256 amountIn,
        uint256 amountOut
    );

    function setUp() public virtual override {
        uint256 mainnetForkBlock = 14787296;
        vm.createSelectFork(vm.rpcUrl("mainnet"), mainnetForkBlock);
        super.setUp();

        vm.startPrank(board);
        curveSwapWrapper = new CurveWrapper("Curve SwapWrapper", ICurveExchange(curveExchange), IWETH9(payable(weth)));
        globalTestRegistry.setSwapWrapperStatus(ISwapWrapper(curveSwapWrapper), true);
        vm.stopPrank();
    }

    function test_swap_AB() public {
        swap(curvePool, tokenA, tokenB, amount, amountOutExpectedB);
    }

    function test_swap_BA() public {
        swap(curvePool, tokenB, tokenA, amount, amountOutExpectedA);
    }

    function swap(
        address _curvePool,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutExpected
    ) public {
        uint256 _amountOut;
        if (_tokenIn == eth) {
            deal(sender, _amountIn);
            // pool, minOut
            bytes memory _data = abi.encode(_curvePool, uint256(0));
            vm.expectEmit(true, true, true, true);
            emit WrapperSwapExecuted(_tokenIn, _tokenOut, sender, receiver, _amountIn, _amountOutExpected);
            vm.prank(sender);
            _amountOut = curveSwapWrapper.swap{value: _amountIn}(_tokenIn, _tokenOut, receiver, _amountIn, _data);
        } else {
            // normally we use user1 and deal, but in stETH's case we change the sender to a stETH holder, so no deal
            if (sender == user1) deal(_tokenIn, sender, _amountIn);
            // To make sure this wrapper works even if an approval has been preset, prank a pre-existing approval
            vm.prank(address(curveSwapWrapper));
            ERC20(_tokenIn).safeApprove(address(curveExchange), 1e2);

            // pool, minOut
            bytes memory _data = abi.encode(_curvePool, uint256(0));
            vm.expectEmit(true, true, true, true);
            emit WrapperSwapExecuted(_tokenIn, _tokenOut, sender, receiver, _amountIn, _amountOutExpected);

            vm.startPrank(sender);
            ERC20(_tokenIn).safeApprove(address(curveSwapWrapper), _amountIn);
            _amountOut = curveSwapWrapper.swap(_tokenIn, _tokenOut, receiver, _amountIn, _data);
            vm.stopPrank();
        }
        if (_tokenOut == eth) {
            if (logAmountOut) console2.log(ERC20(_tokenIn).symbol(), "ETH", _amountOut);
            assertEq(_amountOut, _amountOutExpected);
            assertEq(receiver.balance, _amountOut);
            return;
        }
        if (logAmountOut) {
            if (_tokenIn == eth) _tokenIn = weth;
            console2.log(ERC20(_tokenIn).symbol(), ERC20(_tokenOut).symbol(), _amountOut);
        }

        // Since stETH's balance is computed virtually, allow "off by 1" in assertion
        assertApproxEqAbs(_amountOut, _amountOutExpected, 1);
        assertApproxEqAbs(ERC20(_tokenOut).balanceOf(receiver), _amountOut, 1);
    }
}

contract UsdcDaiSwapTest is CurveWrapperTest {
    function setUp() public override {
        super.setUp();
        tokenA = usdc;
        tokenB = dai;
        curvePool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7; // 3pool
        amountOutExpectedA = 9998156541;
        amountOutExpectedB = 185280378678891553436668111;
    }
}

contract WbtcUsdtSwapTest is CurveWrapperTest {
    function setUp() public override {
        super.setUp();
        tokenA = wbtc;
        tokenB = usdt;
        // Reverts with high amount
        amount = 1e10;
        curvePool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46; // TriCrypto2
        amountOutExpectedA = 33958853;
        amountOutExpectedB = 2860632158925;
    }
}

contract EthStethSwapTest is CurveWrapperTest {
    function setUp() public override {
        super.setUp();
        tokenA = eth;
        tokenB = steth;
        curvePool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022; // steth
        // writing steth balance to storage causes MATH_MUL_OVERFLOW error, so we pick a sender who's already stETH rich
        sender = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
        amount = 1e18;
        amountOutExpectedA = 982738872969376416;
        amountOutExpectedB = 1016750243467508706;
    }
}
