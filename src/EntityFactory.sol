//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import { Org, Fund } from './Entity.sol';
import { ERC20 } from "solmate/tokens/ERC20.sol";

/**
 * @notice EntityFactory is responsible for deploying Funds and Orgs and maintaining a record of said deployment.
 */
contract EntityFactory {

    // --- Storage ---
    /// @notice Admin address can modify system vars
    address public admin;

    /// @notice Maintains a list of the Entities deployed by this factory
    mapping (address => bool) public isEntity;
    
    /// @notice ERC20 token that underlies the system
    ERC20 public baseToken;

    // --- Errors ---
    error Unauthorized();

    // --- Events ---
    event OrgDeployed(Org indexed org, bytes32 indexed orgId);
    event FundDeployed(Fund indexed fund, address indexed manager);
    event BaseTokenSet(address indexed newBaseToken);
    event AdminSet(address indexed newAdmin);

    // --- Constructor ---
    constructor(address _admin, ERC20 _baseToken) {
        admin = _admin;
        baseToken = _baseToken;
    }

    // --- External fns ---

    /**
     * @notice Deploys an org
     * @dev "manager" is not actually set on org, but is used to signal intended manager pending claim
     */
    function deployOrg(bytes32 _orgId) external returns (Org _org) {
        _org = new Org(_orgId);
        isEntity[address(_org)] = true;
        emit OrgDeployed(_org, _orgId);
    }

    /**
     * @notice Deploys a fund
     */
    function deployFund(address _manager) external returns (Fund _fund) {
        _fund = new Fund(_manager);
        isEntity[address(_fund)] = true;
        emit FundDeployed(_fund, _manager);
    }

    /**
     * @notice Set a new ERC20 base token
     */
    function setBaseToken(address _newBaseTokenAddress) external {
        if (msg.sender != admin) revert Unauthorized();
        baseToken = ERC20(_newBaseTokenAddress);
        emit BaseTokenSet(_newBaseTokenAddress);
    }

    /**
     * @notice Set a new 'admin' user account
     */
    function setAdmin(address _newAdmin) external {
        if (msg.sender != admin) revert Unauthorized();
        admin = _newAdmin;
        emit AdminSet(_newAdmin);
    }

}
