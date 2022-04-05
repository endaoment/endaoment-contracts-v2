//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import "./Registry.sol";
import "./Entity.sol";

/**
 * @notice Fund entity
 */
contract Fund is Entity {

    constructor(Registry _registry, address _manager) Entity(_registry, _manager) { }

    function entityType() public pure override returns (uint8) {
        return 2;
    }
}
