// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.12;

contract Dummy {
  uint256 public magicNumber = 0;

  function setNumber(uint256 _number) external returns (string memory) {
    magicNumber = _number;
    return "good job";    
  }
}
