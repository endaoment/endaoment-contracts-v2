// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { console2 } from "forge-std/console2.sol";
abstract contract UniV3WrapperTest is DeployTest {
    using SafeTransferLib for ERC20;
    address tokenA;
    address tokenB;
    uint256 amountOutExpectedA;
    uint256 amountOutExpectedB;
    uint24 fee = 3000;

    // switch flag to true to see amountOuts
    bool logAmountOut = false;

    address eth  = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; 
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address dai  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address sender = user1;
    address receiver = user2;

    event WrapperSwapExecuted(address indexed tokenIn, address indexed tokenOut, address sender, address indexed recipient, uint256 amountIn, uint256 amountOut);

    function test_swap_AB() public {
        uint256 _amount = 1e22;
        swap(tokenA, tokenB, _amount, amountOutExpectedB);
    }

    function test_swap_BA() public {
        uint256 _amount = 1e22;
        swap(tokenB, tokenA, _amount, amountOutExpectedA);
    }
    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _amountOutExpected) public {
        uint256 _amountOut;
        if(_tokenIn == eth) {
            deal(sender, _amountIn);
            // fee, deadline, amountOutMinimum, sqrtPriceLimitX96
            bytes memory _data = abi.encode(uint24(fee), uint256(1649787227), uint256(0), uint160(0));
            vm.expectEmit(true, true, true, true);
            emit WrapperSwapExecuted(_tokenIn, _tokenOut, sender, receiver, _amountIn, _amountOutExpected);
            vm.prank(sender);
            _amountOut = uniV3SwapWrapper.swap{value:_amountIn}(_tokenIn, _tokenOut, sender, receiver, _amountIn, _data);
        } else {
            deal(_tokenIn, sender, _amountIn);
            // To make sure this wrapper works even if an approval has been preset, prank a pre-existing approval
            vm.prank(address(uniV3SwapWrapper));
            ERC20(_tokenIn).safeApprove(address(uniV3SwapRouter), 1e27);

            // fee, deadline, amountOutMinimum, sqrtPriceLimitX96
            bytes memory _data = abi.encode(uint24(fee), uint256(1649787227), uint256(0), uint160(0));
            vm.expectEmit(true, true, true, true);
            emit WrapperSwapExecuted(_tokenIn, _tokenOut, sender, receiver, _amountIn, _amountOutExpected);
            
            vm.startPrank(sender);
            ERC20(_tokenIn).safeApprove(address(uniV3SwapWrapper), _amountIn);
            _amountOut = uniV3SwapWrapper.swap(_tokenIn, _tokenOut, sender, receiver, _amountIn, _data);
            vm.stopPrank();
        }
        if(_tokenOut == eth) {
            if(logAmountOut) console2.log(ERC20(_tokenIn).symbol(), "ETH", _amountOut);
            assertEq(_amountOut, _amountOutExpected);
            assertEq(receiver.balance, _amountOut);
            return;
        }
        if(logAmountOut) {
            if(_tokenIn == eth) _tokenIn = weth;
            console2.log(ERC20(_tokenIn).symbol(), ERC20(_tokenOut).symbol(), _amountOut);
        }
        assertEq(_amountOut, _amountOutExpected);
        assertEq(ERC20(_tokenOut).balanceOf(receiver), _amountOut);
    
    }
}
contract UsdcDaiSwapTest is UniV3WrapperTest {
  function setUp() public override {
    super.setUp();
    tokenA = usdc;
    tokenB = dai;
    amountOutExpectedA = 2578515525;
    amountOutExpectedB = 2663591210195665669008;
  }
}

contract UsdcDaiFee500SwapTest is UniV3WrapperTest {
  function setUp() public override {
    super.setUp();
    tokenA = usdc;
    tokenB = dai;
    fee = 500;
    amountOutExpectedA = 9993657845;
    // the .05% pool has less liquidity so the price impact is much worse
    amountOutExpectedB = 55757825013456110304297360;
  }
}

contract UsdcWbtcSwapTest is UniV3WrapperTest {
  function setUp() public override {
    super.setUp();
    tokenA = usdc;
    tokenB = wbtc;
    amountOutExpectedA = 54841485265367;
    amountOutExpectedB = 133214256164;
  }
}


contract WbtcUsdtSwapTest is UniV3WrapperTest {
  function setUp() public override {
    super.setUp();
    tokenA = wbtc;
    tokenB = usdt;
    amountOutExpectedA = 14025814610;
    amountOutExpectedB = 5818238861822;
  }
}

contract UsdcEthSwapTest is UniV3WrapperTest {
  function setUp() public override {
    super.setUp();
    tokenA = usdc;
    tokenB = eth;
    amountOutExpectedA = 31664705400085;
    amountOutExpectedB = 39196884382268151608637;
  }
}

contract UsdcWethSwapTest is UniV3WrapperTest {
  function setUp() public override {
    super.setUp();
    tokenA = usdc;
    tokenB = weth;
    amountOutExpectedA = 31664705400085;
    amountOutExpectedB = 39196884382268151608637;
  }
}
