//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { ISwapWrapper } from "../interfaces/ISwapWrapper.sol";
import { ISwapRouter } from "../lib/IUniswapV3SwapRouter.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { IWETH9 } from "../lib/IWETH9.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

error ETHAmountInMismatch();

contract UniV3Wrapper is ISwapWrapper {
    using SafeTransferLib for ERC20;

    /// @notice A deployed Uniswap v3 SwapRouter. See https://docs.uniswap.org/protocol/reference/deployments.
    ISwapRouter public immutable swapRouter;

    /// @notice WETH contract.
    IWETH9 public immutable weth;

    /// @notice SwapWrapper name.
    string public name;

    /// @dev Address we use to represent ETH.
    address constant internal eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @param _name SwapWrapper name.
     * @param _uniV3SwapRouter Deployed Uniswap v3 SwapRouter.
     */
    constructor(string memory _name, address _uniV3SwapRouter) {
        name = _name;
        swapRouter = ISwapRouter(_uniV3SwapRouter);
        weth = IWETH9(swapRouter.WETH9());
    }

    /**
     * @notice `swap` handles all swaps on Uniswap v3.
     * @param _tokenIn Token in (or for ETH, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE).
     * @param _tokenOut Token out (or for ETH, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE).
     * @param _sender Sender of swap input.
     * @param _recipient Recipient of the swap output.
     * @param _amount Amount of `_tokenIn`.
     * @param _data Abi encoded `fee`, `deadline`, `amountOutMinimum`, `sqrtPriceLimitX96`.
        e.g. `bytes memory _data = abi.encode(uint24(3000), uint256(1649787227), uint256(0), uint160(0));`
     * @dev In the case of an ERC20 swap, this contract first possesses the `_amount` via `transferFrom`
     * and therefore preconditionally requires an ERC20 approval from the caller.
     */
    function swap(address _tokenIn, address _tokenOut, address _sender, address _recipient, uint256 _amount, bytes calldata _data) external payable returns (uint256) {
        // If token is ETH and value was sent, ensure the value matches the swap input amount.
        bool _isInputEth = _tokenIn == eth || (_tokenIn == address(weth) && msg.value > 0);
        if ((_isInputEth && msg.value != _amount) || (!_isInputEth && msg.value > 0)) revert ETHAmountInMismatch(); 

        // If caller isn't sending ETH, we need to transfer in tokens and approve the router
        if (!_isInputEth) {
            ERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amount);
            // We first set allowance to 0 then to the swap amount because some tokens like USDT do not allow you
            // to change allowance without going through zero. They do this as mitigation against the ERC-20
            // approval race condition, but that race condition is not an issue here.
            ERC20(_tokenIn).safeApprove(address(swapRouter), 0);
            ERC20(_tokenIn).safeApprove(address(swapRouter), _amount);
        }

        // If swapping from ETH, specify WETH as the swap input token. However, we preserve _tokenIn as the ETH
        // address so it can be differentiated in logs.
        address _swapTokenIn = _tokenIn == eth ? address(weth) : _tokenIn;

        // If swapping into ETH, specify WETH as the swap output token. We similarly preserve _tokenOut as the ETH
        // address so it can be differentiated in logs.
        address _swaptokenOut = _tokenOut == eth ? address(weth) : _tokenOut;

        // If swapping to ETH, first swap WETH to this contract (will then be unwrapped and forwarded to recipient).
        address _swapRecipient = _tokenOut == eth ? address(this) : _recipient;

        // Prepare the swap.
        uint256 _amountOut;
        {
            (uint24 _fee, uint256 _deadline, uint256 _amountOutMinimum, uint160 _sqrtPriceLimitX96) = abi.decode(_data, (uint24, uint256, uint256, uint160)); 
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: _swapTokenIn,
                tokenOut: _swaptokenOut,
                fee: _fee,
                recipient: _swapRecipient,
                deadline: _deadline,
                amountIn: _amount,
                amountOutMinimum: _amountOutMinimum,
                sqrtPriceLimitX96: _sqrtPriceLimitX96
            });

            // Execute the swap
            _amountOut = swapRouter.exactInputSingle{value:msg.value}(params);
        }
        // Unwrap WETH for ETH if required.
        if (_tokenOut == eth) {
            weth.withdraw(_amountOut);
            payable(_recipient).transfer(_amountOut);
        }
        emit WrapperSwapExecuted(_tokenIn, _tokenOut, _sender, _recipient, _amount, _amountOut);
        return _amountOut;
    }

    /// @notice Required to receive ETH on `weth.withdraw()`
    receive() external payable {}
}
