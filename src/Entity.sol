//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

import { Registry, Unauthorized } from  "./Registry.sol";

import { Math } from "./lib/Math.sol";

error EntityInactive();
error InsufficientFunds();

/**
 * @notice Entity contract inherited by Org and Fund contracts (and all future kinds of Entities).
 */
abstract contract Entity {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    /// @notice The base registry to which the entity is connected.
    Registry public immutable registry;

    /// @notice The entity's manager.
    address public manager;

    // @notice The base token used for tracking the entity's fund balance.
    ERC20 public immutable baseToken;

    /// @notice The current balance for the entity, denominated in the base token's units.
    uint256 public balance;

    /// @notice Each entity will implement this function to allow a caller to interrogate what kind of entity it is.
    function entityType() public pure virtual returns (uint8);

    /**
     * @param _registry The registry to host the Entity.
     * @param _manager The address of the Entity's manager.
     */
    constructor(Registry _registry, address _manager) {
        registry = _registry;
        manager = _manager;
        baseToken = _registry.baseToken();
    }

    /**
     * @notice Receives a donated amount of base tokens to be added to the entity's balance.
     * @param _amount Amount donated in base token.
     * @dev This function will revert if the entity is inactive or if the token transfer fails.
     */
    function donate(uint256 _amount) external {
        if (!registry.isActiveEntity(this)) revert EntityInactive();

        uint256 _fee = _amount.zocmul(registry.getDonationFee(this));
        uint256 _netAmount = _amount - _fee; // overflow check prevents fee proportion > 0

        baseToken.safeTransferFrom(msg.sender, registry.treasury(), _fee);
        baseToken.safeTransferFrom(msg.sender, address(this), _netAmount);

        balance += _netAmount;
    }

    /**
     * @notice Transfers an amount of base tokens from this entity to another entity.
     * @param _to The entity to receive the tokens.
     * @param _amount Contains the amount being donated (denominated in the base token's units).
     * @dev This function will revert if the entity is inactive or if the token transfer fails.
     * @dev This function will revert `Unauthorized` if the `msg.sender` is not the entity manager.
     * @dev (TODO: Shouldn't revert "unauthorized" if msg.sender is admin/board, ie: "god mode").
     */
    function transfer(Entity _to, uint256 _amount) external {
        if (msg.sender != manager) revert Unauthorized();
        if (!registry.isActiveEntity(this)) revert EntityInactive();
        if (balance < _amount) revert InsufficientFunds();

        uint256 _fee = _amount.zocmul(registry.getTransferFee(this, _to));
        uint256 _netAmount = _amount - _fee;

        baseToken.safeTransferFrom(msg.sender, registry.treasury(), _fee);
        baseToken.safeTransfer(address(_to), _netAmount);

        unchecked {
            balance -= _amount;
        }
    }

    // TODO: God mode for admin
}
