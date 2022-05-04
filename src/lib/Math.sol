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

    // Below is WAD math from solmate's FixedPointMathLib.
    // https://github.com/Rari-Capital/solmate/blob/c8278b3cb948cffda3f1de5a401858035f262060/src/utils/FixedPointMathLib.sol

    uint256 internal constant WAD = 1e18; // The scalar of ETH and most ERC20s.

    function mulWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD); // Equivalent to (x * y) / WAD rounded down.
    }

    function divWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y); // Equivalent to (x * WAD) / y rounded down.
    }

    /*//////////////////////////////////////////////////////////////
                    LOW LEVEL FIXED POINT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // Divide z by the denominator.
            z := div(z, denominator)
        }
    }
}
