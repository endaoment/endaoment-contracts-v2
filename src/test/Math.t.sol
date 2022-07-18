// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "./utils/DSTestPlus.sol";
import {Math} from "../lib/Math.sol";

contract MathTest is DSTestPlus {
    using Math for uint256;

    uint256 internal constant ZOC = 1e4;

    function testFuzz_zocmul(uint256 _x, uint256 _y) public {
        unchecked {
            // if x * y overflows, we shrink the values
            while (_x != 0 && (_x * _y) / _x != _y) {
                _x /= 2;
                _y /= 2;
            }
        }
        assertEq(_x.zocmul(_y), (_x * _y) / ZOC);
    }
}
