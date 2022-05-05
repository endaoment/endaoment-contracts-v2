//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { Clones } from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import { Registry } from "./Registry.sol";
import { EntityFactory } from "./EntityFactory.sol";
import { Org } from "./Org.sol";
import { Fund } from "./Fund.sol";

/**
 * @notice This contract is the factory for both the Org and Fund objects.
 */
contract OrgFundFactory is EntityFactory {

    Org orgImplementation;
    Fund fundImplementation;

    constructor(Registry _registry) EntityFactory(_registry) {
        orgImplementation = new Org();
        orgImplementation.initialize(_registry, bytes32("IMPL")); // necessary?
        fundImplementation = new Fund();
        fundImplementation.initialize(_registry, address(0));
    }

    /**
     * @notice Deploys a Fund.
     * @param _manager The address of the Fund's manager.
     * @param _salt A 32-byte value used to create the contract at a deterministic address.
     * @return _fund The deployed Fund.
     */
    function deployFund(address _manager, bytes32 _salt) public returns (Fund _fund) {
        _fund = Fund(Clones.cloneDeterministic(address(fundImplementation), _salt));
        _fund.initialize(registry, _manager);
        registry.setEntityActive(_fund);
        emit EntityDeployed(address(_fund), _fund.entityType(), _manager);
    }

    /**
     * @notice Deploys an Org.
     * @param _orgId The Org's ID for tax purposes.
     * @param _salt A 32-byte value used to create the contract at a deterministic address.
     * @return _org The deployed Org.
     */
    function deployOrg(bytes32 _orgId, bytes32 _salt) public returns (Org _org) {
        _org = Org(Clones.cloneDeterministic(address(orgImplementation), _salt));
        _org.initialize(registry, _orgId);
        registry.setEntityActive(_org);
        emit EntityDeployed(address(_org), _org.entityType(), _org.manager());
    }

    /**
     * @notice Calculates an Org contract's deployment address.
     * @param _salt A 32-byte value used to create the contract at a deterministic address.
     * @return The Org's deployment address.
     * @dev This function is used off-chain by the automated tests to verify proper contract address deployment.
     */
    function computeOrgAddress(bytes32 _salt) external view returns (address) {
        return Clones.predictDeterministicAddress(address(orgImplementation), _salt, address(this));
    }

    /**
     * @notice Calculates a Fund contract's deployment address.
     * @param _salt A 32-byte value used to create the contract at a deterministic address.
     * @return The Fund's deployment address.
     * @dev This function is used off-chain by the automated tests to verify proper contract address deployment.
     */
    function computeFundAddress(bytes32 _salt) external view returns (address) {
        return Clones.predictDeterministicAddress(address(fundImplementation), _salt, address(this));
    }
}
