// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import "../../Registry.sol";
import "../../OrgFundFactory.sol";
import "../../lib/Math.sol";

/**
 * @dev Deploys Endaoment contracts
 * @dev Test harness, eventually deploy script (https://github.com/gakonst/foundry/issues/402)
 */
contract DeployAll {
  address immutable self;
  uint256 constant MAX_UINT = type(uint256).max;
  address constant board = address(0x1);
  address constant treasury = address(0xface);
  address constant user1 = address(0xabc1);
  address constant user2 = address(0xabc2);
  address constant capitalCommittee = address(0xccc);
  address constant programCommittee = address(0xbbbb);

  /// @notice special address that is used to give permissions for entity operations
  address constant entityPerms = address(bytes20("entity"));

  Registry globalTestRegistry;
  OrgFundFactory orgFundFactory;
  MockERC20 baseToken;

  constructor() {
    self = address(this); // convenience
    setUp(); // support echidna
  }

  function setUp() public virtual {
    baseToken = new MockERC20("USD Coin", "USDC", 6);
    globalTestRegistry = new Registry(board, treasury, baseToken);
    orgFundFactory = new OrgFundFactory(globalTestRegistry);
  }
}
