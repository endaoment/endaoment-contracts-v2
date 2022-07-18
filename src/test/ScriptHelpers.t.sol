// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "./utils/DSTestPlus.sol";
import {ScriptHelpers} from "../../script/ScriptHelpers.s.sol";

contract ScriptHelpersTest is DSTestPlus, ScriptHelpers {
    function testFuzz_stringToAddress(address _addressToTest) public {
        string memory _testAddressString = vm.toString(_addressToTest);

        address _resultAddress = stringToAddress(_testAddressString);
        assertEq(_resultAddress, _addressToTest);
    }

    function test_stringToAddressFailsWithoutPrefix() public {
        string memory _testAddressString = "a0Ee7A142d267C1f36714E4a8F75612F20a79720";

        vm.expectRevert(stdError.indexOOBError);
        stringToAddress(_testAddressString);
    }

    function test_stringToBytes32EmptyString() public {
        string memory _testString = "";

        bytes32 _resultBytes = stringToBytes32(_testString);
        assertEq(_resultBytes, "");
    }

    function test_stringToBytes32Alpha() public {
        string memory _testString = "abcdefg";

        bytes32 _resultBytes = stringToBytes32(_testString);
        assertEq(_resultBytes, "abcdefg");
    }

    function test_stringToBytes32Numeric() public {
        string memory _testString = "1234567";

        bytes32 _resultBytes = stringToBytes32(_testString);
        assertEq(_resultBytes, "1234567");
    }

    function test_stringToBytes32AlphaNumeric() public {
        string memory _testString = "123abc4567";

        bytes32 _resultBytes = stringToBytes32(_testString);
        assertEq(_resultBytes, "123abc4567");
    }
}
