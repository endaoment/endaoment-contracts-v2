//SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import { ISwapWrapper, ETHAmountInMismatch } from "../interfaces/ISwapWrapper.sol";
import { ICurveExchange } from "../interfaces/ICurveExchange.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { IWETH9 } from "../lib/IWETH9.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

contract CurveWrapper is ISwapWrapper {
    using SafeTransferLib for ERC20;

    /// @notice Curve Exchange contract, used to route pool exchanges.
    ICurveExchange public immutable curveExchange;

    /// @notice WETH contract.
    IWETH9 public immutable weth;

    /// @notice SwapWrapper name.
    string public name;

    /// @dev Address we use to represent ETH.
    address constant internal eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @param _name SwapWrapper name.
     * @param _curveExchange Curve swap exchange.
     * @param _weth WETH address.
     */
    constructor(string memory _name, ICurveExchange _curveExchange, IWETH9 _weth) {
        name = _name;
        curveExchange = _curveExchange;
        weth = _weth;
    }

    /**
     * @notice `swap` handles all swaps on Curve.
     * @param _tokenIn Token in (or for ETH, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE).
     * @param _tokenOut Token out (or for ETH, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE).
     * @param _recipient Recipient of the swap output.
     * @param _amount Amount of `_tokenIn`.
     * @param _data Abi encoded `curvePool` and `minOut`
        e.g. `bytes memory _data = abi.encode(address(curvePool), uint256(minOut));`
     * @dev In the case of an ERC20 swap, this contract first possesses the `_amount` via `transferFrom`
     * and therefore preconditionally requires an ERC20 approval from the caller.
     */
    function swap(address _tokenIn, address _tokenOut, address _recipient, uint256 _amount, bytes calldata _data) external payable returns (uint256) {
        (address _curvePool, uint256 _minOut) = abi.decode(_data, (address, uint256));
        // CONSIDER: Do we need pool whitelist?
        // Perhaps there exists a theoretical attack that some Entity looking to siphon out funds would somehow get their attack pool approved on the Curve registry,
        // and somehow abscond with some amount of tokenIn. Seems pretty tenuous.
        // Perhaps if an attacker persuaded an Entity manager to route through malicious pool (how would this happen?) then attacker could abscond funds.
        
        {
            // If token is ETH and value was sent, ensure the value matches the swap input amount.
            bool _isInputEth = _tokenIn == eth;
            if ((_isInputEth && msg.value != _amount) || (!_isInputEth && msg.value > 0)) revert ETHAmountInMismatch(); 
            
            // If caller isn't sending ETH, we need to transfer in tokens and approve the router
            if (!_isInputEth) {
                ERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amount);
                // We first set allowance to 0 then to the swap amount because some tokens like USDT do not allow you
                // to change allowance without going through zero. They do this as mitigation against the ERC-20
                // approval race condition, but that race condition is not an issue here.
                ERC20(_tokenIn).safeApprove(address(curveExchange), 0);
                ERC20(_tokenIn).safeApprove(address(curveExchange), _amount);
            }
        }
        uint256 _amountOut = curveExchange.exchange{value:msg.value}(_curvePool, _tokenIn, _tokenOut, _amount, _minOut, _recipient);
        emit WrapperSwapExecuted(_tokenIn, _tokenOut, msg.sender, _recipient, _amount, _amountOut);
        return _amountOut;
    }

    /// @notice Required to receive ETH on `weth.withdraw()`
    receive() external payable {}
}
