//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import "./Registry.sol";
import "./Entity.sol";

/**
 * @notice Org entity
 */
contract Org is Entity {
    
    /// @notice Tax ID of org
    bytes32 public orgId;

    constructor(bytes32 _orgId, Registry _registry, address _manager) Entity(_registry, _manager) {
        orgId = _orgId;
    }

    function entityType() public pure override returns (uint8) {
        return 1;
    }
}
