//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import { EntityFactory } from './EntityFactory.sol';

/**
 * @notice Entity contract inherited by Org and Fund
 */
abstract contract Entity {

    /// --- Storage ---
    /// @notice Manager with privileged permission on Entity
    address public manager;

    /// @notice The Endaoment EntityFactory that deployed this Entity
    EntityFactory public immutable entityFactory;

    /**
     * @notice Flag to disable an entity
     * @dev Should be checked on certain Entity operations
     */ 
    bool public disabled = false;

    /// --- Constructor ---
    constructor(address _manager) {
        manager = _manager;
        entityFactory = EntityFactory(msg.sender);
    }

    /// --- Virtual fns ---
    function isOrg() public virtual returns (bool);
}

/**
 * @notice Org entity
 */
contract Org is Entity {
    
    /// --- Storage ---
    /// @notice Tax ID of org
    bytes32 public orgId;

    /// --- Constructor ---
    constructor(bytes32 _orgId) Entity(address(0)) {
        orgId = _orgId;
    }
    
    /// --- Overrides ---
    function isOrg() public pure override returns (bool) {
        return true;
    }
}


/**
 * @notice Fund entity
 */
contract Fund is Entity {

    /// --- Constructor ---
    constructor(address _manager) Entity(_manager) {}

    /// --- Overrides ---
    function isOrg() public pure override returns (bool) {
        return false;
    }
}
