// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";

contract RegistryTest is DeployTest {
}

contract RegistryConstructor is RegistryTest {

  function testRegistryConstructor(address _admin, address _treasury, address _baseToken) public {
    Registry _registry = new Registry(_admin, _treasury, ERC20(_baseToken));
    assertEq(_registry.admin(), _admin);
    assertEq(_registry.treasury(), _treasury);
    assertEq(address(_registry.baseToken()), _baseToken);
  }
}

