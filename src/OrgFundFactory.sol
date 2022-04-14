//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { Create2 } from "openzeppelin-contracts/contracts/utils/Create2.sol";

import { Registry } from "./Registry.sol";
import { Org } from "./Org.sol";
import { Fund } from "./Fund.sol";

/**
 * @notice This contract is the factory for both the Org and Fund objects.
 */
contract OrgFundFactory {

    /// @notice The registry that the factory will operate upon.
    Registry public immutable registry;

    constructor(Registry _registry) {
        registry = _registry;
    }

    /**
     * @notice Deploys a Fund.
     * @param _manager The address of the Fund's manager.
     * @param _salt A 32-byte value used to create the contract at a deterministic address.
     * @return _fund The deployed Fund.
     */
    function deployFund(address _manager, bytes32 _salt) public returns (Fund _fund) {
        // TODO: validations?
        _fund = new Fund {salt: _salt} (registry, _manager);
        registry.setEntityStatus(_fund, true);
    }

    /**
     * @notice Deploys an Org.
     * @param _orgId The Org's ID for tax purposes.
     * @param _salt A 32-byte value used to create the contract at a deterministic address.
     * @return _org The deployed Org.
     */
    function deployOrg(bytes32 _orgId, bytes32 _salt) public returns (Org _org) {
        _org = new Org {salt: _salt} (registry, _orgId);
        registry.setEntityStatus(_org, true);
    }
    
    /**
     * @notice Calculates an Org contract's deployment address.
     * @param _orgId The Org's ID for tax purposes (needed to replicate constructor args for CREATE2).
     * @param _salt A 32-byte value used to create the contract at a deterministic address.
     * @return The Org's deployment address.
     * @dev This function is used off-chain by the automated tests to verify proper contract address deployment.
     */
    function computeOrgAddress(bytes32 _orgId, bytes32 _salt) external view returns (address) {
        bytes memory _constructorArgs = abi.encode(registry, _orgId);
        bytes32 _orgCodeHash = keccak256(abi.encodePacked(type(Org).creationCode, _constructorArgs));
        return Create2.computeAddress(_salt, _orgCodeHash, address(this));
    }

    /**
     * @notice Calculates a Fund contract's deployment address.
     * @param _manager The address of the Fund's manager (needed to replicate constructor args for CREATE2).
     * @param _salt A 32-byte value used to create the contract at a deterministic address.
     * @return The Fund's deployment address.
     * @dev This function is used off-chain by the automated tests to verify proper contract address deployment.
     */
    function computeFundAddress(address _manager, bytes32 _salt) external view returns (address) {
        bytes memory _constructorArgs = abi.encode(registry, _manager);
        bytes32 _fundCodeHash = keccak256(abi.encodePacked(type(Fund).creationCode, _constructorArgs));
        return Create2.computeAddress(_salt, _fundCodeHash, address(this));
    }
}
