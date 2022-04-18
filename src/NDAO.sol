//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { ERC20 } from "solmate/tokens/ERC20.sol";

/**
 * @notice The NDAO ERC20 token. It can be staked to receive NVT Governance tokens.
 */
contract NDAO is ERC20 {

    /// @notice The privileged address which is able to mint more NDAO.
    address public admin;

    /// @notice Thrown when non-admin user attempts to mint NDAO.
    error Unauthorized();

    /// @notice Emitted when the admin is changed.
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    /// @param _admin The admin address which will be able to mint more NDAO.
    constructor(
        address _admin
    ) ERC20("NDAO", "NDAO", 18) {
        admin = _admin;
        emit AdminUpdated(address(0), _admin);
    }

    /**
     * @notice Mint more NDAO tokens; must be called by admin.
     * @param _to Address where newly minted tokens will be sent.
     * @param _amount Amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) public {
        if (msg.sender != admin) revert Unauthorized();
        _mint(_to, _amount);
    }

    /**
     * @notice Allows admin to set new admin.
     * @param _newAdmin The address of the new admin account.
     */
    function updateAdmin(address _newAdmin) public {
        if (msg.sender != admin) revert Unauthorized();
        emit AdminUpdated(admin, _newAdmin);
        admin = _newAdmin;
    }
}
