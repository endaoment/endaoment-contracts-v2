//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { EndaomentAuth } from "./lib/auth/EndaomentAuth.sol";
import { RolesAuthority } from "./lib/auth/authorities/RolesAuthority.sol";

/**
 * @notice The NDAO ERC20 token. It can be staked to receive NVT Governance tokens.
 */
contract NDAO is ERC20, EndaomentAuth {

    /// @param _authority The address of the authority which defines permissions for NDAO minting.
    constructor(
        RolesAuthority _authority
    ) ERC20("NDAO", "NDAO", 18) EndaomentAuth(_authority, "") { }

    /**
     * @notice Mint more NDAO tokens; must be called by admin.
     * @param _to Address where newly minted tokens will be sent.
     * @param _amount Amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) public requiresAuth {
        _mint(_to, _amount);
    }
}
