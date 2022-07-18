pragma solidity 0.8.13;

import "forge-std/Script.sol";

/**
 * @notice ScriptHelpers - Contract that provides scripting and related utilities.
 */
contract ScriptHelpers is Script {
    string public jsonDeploysPath = "./broadcast/";

    /**
     * @notice Convert a string to a bytes32 value.
     * @param _source The string to be converted.
     * @return _result The result of the conversion.
     */
    function stringToBytes32(string memory _source) public pure returns (bytes32 _result) {
        assembly {
            _result := mload(add(_source, 32))
        }
    }

    /**
     * @notice Convert a string to an address value.
     * @param _source String to be converted.
     * @return _parsedAddress Converted address from string.
     */
    function stringToAddress(string memory _source) public pure returns (address _parsedAddress) {
        bytes memory tmp = bytes(_source);
        uint160 iaddr = 0;
        uint160 b1;
        uint160 b2;
        for (uint256 i = 2; i < 2 + 2 * 20; i += 2) {
            iaddr *= 256;
            b1 = uint160(uint8(tmp[i]));
            b2 = uint160(uint8(tmp[i + 1]));
            if ((b1 >= 97) && (b1 <= 102)) {
                b1 -= 87;
            } else if ((b1 >= 65) && (b1 <= 70)) {
                b1 -= 55;
            } else if ((b1 >= 48) && (b1 <= 57)) {
                b1 -= 48;
            }
            if ((b2 >= 97) && (b2 <= 102)) {
                b2 -= 87;
            } else if ((b2 >= 65) && (b2 <= 70)) {
                b2 -= 55;
            } else if ((b2 >= 48) && (b2 <= 57)) {
                b2 -= 48;
            }
            iaddr += (b1 * 16 + b2);
        }
        return address(iaddr);
    }
}
