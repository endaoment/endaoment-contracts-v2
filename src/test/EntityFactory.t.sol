// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import { Org, Fund } from "../Entity.sol";

contract EntityTest is DeployTest { 
  function setUp() public virtual override {
    super.setUp();
    // additional config goes here
  }
}

contract EntityFactoryTest is EntityTest {

  function setUp() public override {
    super.setUp();
  }

  function testConstructor(address _admin, address _baseToken) public {
    EntityFactory entityFactory = new EntityFactory(_admin, ERC20(_baseToken));
    assertEq(entityFactory.admin(), _admin);
    assertEq(address(entityFactory.baseToken()), _baseToken);
  }
  
  function testDeployOrg(bytes32 _entityId) public {
    Org org = entityFactory.deployOrg(_entityId);
    assertEq(address(org.entityFactory()), address(entityFactory));
    assertEq(org.manager(), address(0));
    assertEq(org.orgId(), _entityId);
  }

  function testDeployFund(address _manager, bool _onBehalf) public {
    if(!_onBehalf) vm.prank(_manager);
    Fund fund = entityFactory.deployFund(_manager);
    assertEq(address(fund.entityFactory()), address(entityFactory));
    assertEq(fund.manager(), _manager);
  }

  function testIsEntity(address _notAnEntity, address _manager) public {
    Fund fund = entityFactory.deployFund(_manager);
    assertFalse(entityFactory.isEntity(_notAnEntity));
    assertTrue(entityFactory.isEntity(address(fund)));
  }
}
