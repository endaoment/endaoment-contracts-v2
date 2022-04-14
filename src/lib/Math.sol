// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

library Math {
    uint256 internal constant ZOC = 1e4;

    /**
     * @dev Multiply 2 numbers where at least one is a zoc, return product in original units of the other number.
     */
    function zocmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        unchecked {
            z /= ZOC;
        }
    }
}
