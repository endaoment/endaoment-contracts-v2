//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { ISwapWrapper, ETHAmountInMismatch } from "../interfaces/ISwapWrapper.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { IWETH9 } from "../lib/IWETH9.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Registry } from "../Registry.sol";

error UnsupportedSwapper();

contract MultiSwapWrapper is ISwapWrapper {
    using SafeTransferLib for ERC20;

    /// @notice SwapWrapper name.
    string public name;

    /// @notice WETH.
    IWETH9 weth;

    /// @notice Endaoment registry.
    Registry immutable registry;

    /// @dev Address we use to represent ETH.
    address constant internal eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct SwapCursor {
        uint16 nSwaps;
        uint256 cursor;
    }

    struct Swap {
        ISwapWrapper wrapper;
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 amountIn;
    }

    error TokenOutMismatch(address token);

    /**
     * @param _name SwapWrapper name.
     * @param _weth WETH address.
     */
    constructor(string memory _name, IWETH9 _weth, Registry _registry) {
        name = _name;
        weth = _weth;
        registry = _registry;
    }

    /**
     * @notice `swap` handles swaps that should go through multiple swap wrappers.
     * @param _tokenIn Token in (or for ETH, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE).
     * @param _tokenOut Token out (or for ETH, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE).
     * @param _recipient Recipient of the swap output.
     * @param _amount Amount of `_tokenIn`.
     * @param _data Encoded data of the following shape:
     *   e.g. `bytes memory _data = bytes.concat(bytes2(nSwaps), nSwaps[bytes20 wrapperAddress, bytes20 tokenOut, bytes4 payloadLength, bytes{payloadLength} swapPayload])`
     *   where the bracketed payload (bracketed for clarity but syntax can ignore) should be repeated nSwaps times. 
     * @dev In the case of an ERC20 swap, this contract first possesses the `_amount` via `transferFrom`
     * and therefore preconditionally requires an ERC20 approval from the caller.
     */
    function swap(address _tokenIn, address _tokenOut, address _recipient, uint256 _amount, bytes calldata _data) external payable returns (uint256) {

        // Initialize some values for our nextSwap; this struct is required for stack too deep reasons.
        Swap memory nextSwap = Swap(ISwapWrapper(address(0)), _tokenIn, address(0), address(0), _amount);

        // If token is ETH and value was sent, ensure the value matches the swap input amount.
        bool _isInputEth = _tokenIn == eth || (_tokenIn == address(weth) && msg.value > 0);
        if ((_isInputEth && msg.value != _amount) || (!_isInputEth && msg.value > 0)) revert ETHAmountInMismatch(); 
        
        // If caller isn't sending ETH, we need to transfer in tokens.
        if (!_isInputEth) {
            ERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amount);
        }
        // bracketed for stack too deep concerns
        {
            SwapCursor memory swapCursor = SwapCursor(uint16(bytes2(_data[:2])), 2);
            for(uint16 i = 0; i < swapCursor.nSwaps; i++) {
                // each swap's encoding is as follows:
                // [bytes20 wrapperAddress, bytes20 tokenOut, bytes4 payloadLength, bytes[payloadLength] swapPayload]
                nextSwap.wrapper = ISwapWrapper(address(bytes20(_data[swapCursor.cursor : swapCursor.cursor + 20])));
                if(!registry.isSwapperSupported(nextSwap.wrapper)) revert UnsupportedSwapper();
                if(i != 0) nextSwap.tokenIn = nextSwap.tokenOut;
                nextSwap.tokenOut = address(bytes20(_data[swapCursor.cursor + 20 : swapCursor.cursor + 40])); // AKA tokenOut
                if(i == swapCursor.nSwaps - 1 && nextSwap.tokenOut != _tokenOut) revert TokenOutMismatch(nextSwap.tokenIn);

                // We first set allowance to 0 then to the swap amount because some tokens like USDT do not allow you
                // to change allowance without going through zero. They do this as mitigation against the ERC-20
                // approval race condition, but that race condition is not an issue here.
                ERC20(nextSwap.tokenIn).safeApprove(address(nextSwap.wrapper), 0);
                ERC20(nextSwap.tokenIn).safeApprove(address(nextSwap.wrapper), nextSwap.amountIn);

                // if this is the last swap, let child wrapper send to recipient
                nextSwap.recipient = i != swapCursor.nSwaps - 1 ? address(this) : _recipient;

                nextSwap.amountIn = _swap(
                    nextSwap.wrapper,
                    nextSwap.tokenIn,
                    nextSwap.tokenOut,
                    nextSwap.recipient,
                    nextSwap.amountIn,
                    // because of stack too deep error, we cannot define payloadLength as bytes4(_data[swapCursor.cursor + 40 : swapCursor.cursor + 44]), so we inline it
                    _data[swapCursor.cursor + 44 : swapCursor.cursor + 44 + uint32(bytes4(_data[swapCursor.cursor + 40 : swapCursor.cursor + 44]))]);
                // advance the cursor to the start of the next swap payload; again we inline payloadLength as bytes4(_data[swapCursor.cursor + 40 : swapCursor.cursor + 44]))
                swapCursor.cursor += 44 + uint32(bytes4(_data[swapCursor.cursor + 40 : swapCursor.cursor + 44]));
            }
            emit WrapperSwapExecuted(_tokenIn, _tokenOut, msg.sender, _recipient, _amount, nextSwap.amountIn);
            return nextSwap.amountIn; // there is no nextSwap, but this is where the amountOut from the last swap is stored
        }
    }

    /// @dev Internal swap method to carry out the swap. Helpful to avoid stack too deep problem.
    function _swap(ISwapWrapper _wrapper, address _tokenIn, address _tokenOut, address _recipient, uint256 _amount, bytes calldata _data) internal returns (uint256) {
        return _wrapper.swap{value: _tokenIn == eth ? _amount : 0}(_tokenIn, _tokenOut, _recipient, _amount, _data);
    }

    /// @notice Required to receive ETH
    receive() external payable {}
}
