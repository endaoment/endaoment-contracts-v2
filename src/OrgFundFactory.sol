//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import "./Registry.sol";
import "./Org.sol";
import "./Fund.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

contract OrgFundFactory {

    Registry public immutable registry;

    constructor(Registry _registry) {
        registry = _registry;
    }

    function deployFund() public {
        // TODO: validations?
        // TODO: use CREATE2
        Fund newFund = new Fund(registry, msg.sender);
        registry.setEntityStatus(newFund, true);
    }

    function deployOrg(bytes32 _orgId) public {
        Org newOrg = new Org(_orgId, registry, msg.sender);
        registry.setEntityStatus(newOrg, false);
    }
}
