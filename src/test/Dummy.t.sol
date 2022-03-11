// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.12;

import "./utils/DSTestPlus.sol";
import "../Dummy.sol";
import "../lib/Math.sol";

contract DummyTest is DSTestPlus {
  uint256 constant MAX_UINT = type(uint256).max;
  address immutable self;
  Dummy dummy;

  constructor() {
    self = address(this);
  }

  function setUp() public virtual {
    dummy = new Dummy();
  }
}


contract BoringTest is DummyTest {

  function setUp() public override {
    super.setUp();
  }
  
  function testNumber(uint256 _number) public {
    string memory val = dummy.setNumber(_number);
    uint256 newNumber = dummy.magicNumber();
    assertEq(_number, newNumber);
  }
}
