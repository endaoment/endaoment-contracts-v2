// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./DeployTest.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ISwapWrapper, ETHAmountInMismatch } from "../../interfaces/ISwapWrapper.sol";
import { DSTestPlus } from "./DSTestPlus.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";

contract MockSwapperTestHarness is DeployTest {
    using SafeTransferLib for ERC20;
    MockSwapWrapper mockSwapWrapper;
    MockERC20 testToken1;

    function setUp() public override virtual {
        super.setUp();
        mockSwapWrapper = new MockSwapWrapper();
        vm.prank(board);
        globalTestRegistry.setSwapWrapperStatus(mockSwapWrapper, true);
        testToken1 = new MockERC20("test token", "TT", 18);
    }
}

contract MockSwapWrapper is ISwapWrapper, DSTestPlus {
    using SafeTransferLib for ERC20;
    address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public amountOut = 123456e18;
    string public name = "MockSwapWrapper";

    function setAmountOut(uint256 _amountOut) public {
        amountOut = _amountOut;
    }

    function swap(address _tokenIn, address _tokenOut, address _recipient, uint256 _amount, bytes calldata /** _data */) external payable returns (uint256) {
         // If token is ETH and value was sent, ensure the value matches the swap input amount.
        bool _isInputEth = _tokenIn == eth;
        bool _isOutputEth = _tokenOut == eth;
        // If caller isn't sending ETH, we need to transfer in tokens and approve the router
        if(_isInputEth && msg.value == 0) revert ETHAmountInMismatch();
        if (!_isInputEth) {
            ERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amount);
        }
        if(_isOutputEth) {
            deal(_recipient, amountOut);
        } else {
            MockERC20(_tokenOut).mint(_recipient, amountOut);
        }
        return amountOut;
    }

    receive() external payable {}
}
