//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { Registry } from "./Registry.sol";
import { Entity } from "./Entity.sol";

/**
 * @notice Fund entity
 */
contract Fund is Entity {

    /**
     * @param _registry The registry to host the Fund Entity.
     * @param _manager The fund manager.
     */
    constructor(Registry _registry, address _manager) Entity(_registry, _manager) { }

    /**
     * @inheritdoc Entity
     */
    function entityType() public pure override returns (uint8) {
        return 2;
    }
}
