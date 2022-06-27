//SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import { Registry } from "./Registry.sol";
import { Entity } from "./Entity.sol";

/**
 * @notice Fund entity
 */
contract Fund is Entity {

    /**
     * @inheritdoc Entity
     */
    function entityType() public pure override returns (uint8) {
        return 2;
    }
}
