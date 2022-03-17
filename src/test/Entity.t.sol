// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import { Org, Fund } from "../Entity.sol";

contract EntityDeployTest is DeployTest { 
  function setUp() public virtual override {
    super.setUp();
    // additional config goes here
  }
}

contract OrgTest is EntityDeployTest {
  Org org;
  bytes32 orgId = "120-414-411";
  function setUp() public override {
    super.setUp();
    org = entityFactory.deployOrg(orgId);
  }

  function testConstructor() public {
    assertEq(org.manager(), address(0));
    assertEq(org.orgId(), orgId);
    assertFalse(org.disabled());
  }

  function testIsOrg() public {
    assertTrue(org.isOrg());
  }
}

contract FundTest is EntityDeployTest {
  Fund fund;
  function setUp() public override {
    super.setUp();
    fund = entityFactory.deployFund(user1);
  }


  function testConstructor() public {
    assertEq(fund.manager(), address(user1));
    assertFalse(fund.disabled());
  }

  function testIsOrg() public {
    assertFalse(fund.isOrg());
  }
}
