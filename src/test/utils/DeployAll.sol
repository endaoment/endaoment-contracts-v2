// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.12;

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import "../../EntityFactory.sol";
import "../../lib/Math.sol";

/**
 * @dev Deploys Endaoment contracts
 * @dev Test harness, eventually deploy script (https://github.com/gakonst/foundry/issues/402)
 */
contract DeployAll {
  address immutable self;
  uint256 constant MAX_UINT = type(uint256).max;
  address constant admin = address(0x1);
  address constant user1 = address(0xabc1);

  EntityFactory entityFactory;
  MockERC20 baseToken;

  constructor() {
    self = address(this); // convenience
    setUp(); // support echidna
  }

  function setUp() public virtual {
    baseToken = new MockERC20("USD Coin", "USDC", 6);
    entityFactory = new EntityFactory(admin, baseToken);
 }
}
