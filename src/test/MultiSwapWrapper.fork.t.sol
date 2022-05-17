// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { console2 } from "forge-std/console2.sol";
import { MultiSwapWrapper } from "../swapWrappers/MultiSwapWrapper.sol";
import { CurveWrapper } from "../swapWrappers/CurveWrapper.sol";
import { ICurveExchange } from "../interfaces/ICurveExchange.sol";
import { IWETH9 } from "../lib/IWETH9.sol";

contract MultiSwapWrapperTest is DeployTest {
    using SafeTransferLib for ERC20;
    address ethStethCurvePool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    // switch flag to true to see amountOuts
    bool logAmountOut = false;

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address eth  = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address steth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address sender = user1;
    address receiver = user2;
    uint256 amount = 1e6;
    uint256 amountOutExpected = 508109289773032;

    event WrapperSwapExecuted(address indexed tokenIn, address indexed tokenOut, address sender, address indexed recipient, uint256 amountIn, uint256 amountOut);

    function setUp() public virtual override {
      super.setUp();

      vm.startPrank(board);
      uniV3SwapWrapper = new UniV3Wrapper("UniV3 SwapRouter", uniV3SwapRouter);
      curveSwapWrapper = new CurveWrapper("Curve SwapWrapper", ICurveExchange(curveExchange), IWETH9(payable(weth)));
      multiSwapWrapper = new MultiSwapWrapper("Multiswap wrapper", IWETH9(payable(weth)), globalTestRegistry);
      globalTestRegistry.setSwapWrapperStatus(ISwapWrapper(uniV3SwapWrapper), true);
      globalTestRegistry.setSwapWrapperStatus(ISwapWrapper(curveSwapWrapper), true);
      globalTestRegistry.setSwapWrapperStatus(ISwapWrapper(multiSwapWrapper), true);
      vm.stopPrank();
    }

    function test_swap_multi() public {
      uint256 _amountOut;
        
      deal(usdc, sender, amount);
      // To make sure this wrapper works even if an approval has been preset, prank a pre-existing approval
      vm.prank(address(multiSwapWrapper));
      ERC20(usdc).safeApprove(address(uniV3SwapRouter), 1e2);


      // each swap needs [bytes20 wrapper address, bytes20 tokenOut, bytes4 payloadLength, bytesPAYLOADLENGTH data]
      bytes memory swap1Payload = bytes.concat(
        abi.encode(uint256(2649787227), uint256(0)),
        bytes.concat(bytes20(usdc), abi.encodePacked(uint24(3000)), bytes20(weth))
      );
      bytes memory swap2Payload = abi.encode(ethStethCurvePool, uint256(0));
      bytes memory _data = bytes.concat(
        bytes2(uint16(2)), // payload should start with bytes2 of nSwaps
        
        // first swap: uniswap usdc to eth
        // [bytes20 wrapper address, bytes20 tokenOut, bytes4 payloadLength, bytesPAYLOADLENGTH data]
        bytes20(address(uniV3SwapWrapper)),
        bytes20(eth),
        abi.encodePacked(uint32(swap1Payload.length)),
        swap1Payload,
        
        // second swap: curve eth to stETH
        // [bytes20 wrapper address, bytes20 tokenOut, bytes4 payloadLength, bytesPAYLOADLENGTH data]        
        bytes20(address(curveSwapWrapper)),
        bytes20(steth),
        abi.encodePacked(uint32(swap2Payload.length)),
        swap2Payload
      );

      vm.expectEmit(true, true, true, true);
      emit WrapperSwapExecuted(usdc, steth, sender, receiver, amount, amountOutExpected);

      vm.startPrank(sender);
      ERC20(usdc).safeApprove(address(multiSwapWrapper), amount);
      _amountOut = multiSwapWrapper.swap(usdc, steth, receiver, amount, _data);
      vm.stopPrank();
      
      if(logAmountOut) {
          console2.log(ERC20(usdc).symbol(), ERC20(steth).symbol(), _amountOut);
      }

      assertApproxEqAbs(_amountOut, amountOutExpected, 1);
      // Since stETH's balance is computed virtually, allow "off by 2" in assertion
      assertApproxEqAbs(ERC20(steth).balanceOf(receiver), _amountOut, 1);
  }
}
