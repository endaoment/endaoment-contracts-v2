// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import { Org, Fund } from "../Entity.sol";

// --- Errors ---
error Unauthorized();

contract EntityFactoryConstructor is DeployTest {

  function testConstructor(address _admin, address _baseToken) public {
    EntityFactory entityFactory = new EntityFactory(_admin, ERC20(_baseToken));
    assertEq(entityFactory.admin(), _admin);
    assertEq(address(entityFactory.baseToken()), _baseToken);
  }
}
  
contract EntityFactoryDeployOrg is DeployTest {

  function testDeployOrg(bytes32 _entityId) public {
    Org org = entityFactory.deployOrg(_entityId);
    assertEq(address(org.entityFactory()), address(entityFactory));
    assertEq(org.manager(), address(0));
    assertEq(org.orgId(), _entityId);
  }
}

contract EntityFactoryDeployFund is DeployTest {

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

contract EntityFactorySetBaseToken is DeployTest {

  function testSetBaseToken(address _newBaseToken) public {
    vm.prank(admin);
    entityFactory.setBaseToken(_newBaseToken);
    assertEq(address(entityFactory.baseToken()), _newBaseToken);
  }
  
  function testSetBaseTokenUnauthorized(address _newBaseTokenAddress, address _from) public {
    address _originalBaseTokenAddress = address(entityFactory.baseToken());
    vm.assume(_from != admin);
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
    entityFactory.setBaseToken(_newBaseTokenAddress);
    assertEq(address(entityFactory.baseToken()), _originalBaseTokenAddress);
  }
}

contract EntityFactorySetAdmin is DeployTest {

  function testSetAdmin(address _newAdmin) public {
    vm.prank(admin);
    entityFactory.setAdmin(_newAdmin);
    assertEq(_newAdmin, entityFactory.admin());
  }

  function testSetAdminUnauthorized(address _newAdmin, address _from) public {
    vm.assume(_from != admin);
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
    entityFactory.setAdmin(_newAdmin);
  }
}
