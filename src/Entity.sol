//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

import { Registry, Unauthorized } from  "./Registry.sol";
import { Auth, Authority } from "./lib/auth/Auth.sol";
import { Math } from "./lib/Math.sol";

error EntityInactive();
error InsufficientFunds();
error InvalidAction();

/**
 * @notice Entity contract inherited by Org and Fund contracts (and all future kinds of Entities).
 */
abstract contract Entity is Auth {
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

    /// @notice Emitted when manager is set.
    event EntityManagerSet(address indexed oldManager, address indexed newManager);

    /**
     * @notice Modifier for methods that require auth and that the manager cannot access.
     * @dev Overridden from Auth.sol. Reason: use custom error.
     */
    modifier requiresAuth override {
        if(!isAuthorized(msg.sender, msg.sig)) revert Unauthorized();

        _;
    }

    /**
     * @notice Modifier for methods that require auth and that the manager can access.
     * @dev Uses the same condition as `requiresAuth` but with added manager access.
     */
    modifier requiresManager {
        if(msg.sender != manager && !isAuthorized(msg.sender, msg.sig)) revert Unauthorized();
        _;
    }
    
    /// @notice Each entity will implement this function to allow a caller to interrogate what kind of entity it is.
    function entityType() public pure virtual returns (uint8);

    /**
     * @param _registry The registry to host the Entity.
     * @param _manager The address of the Entity's manager.
     */
    constructor(Registry _registry, address _manager) Auth(address(0), _registry) {
        registry = _registry;
        manager = _manager;
        baseToken = _registry.baseToken();
    }

    /**
     * @notice Set a new manager for this entity.
     * @param _manager Address of new manager.
     * @dev Callable by current manager or permissioned role.
     */
    function setManager(address _manager) external requiresManager {
        emit EntityManagerSet(manager, _manager);
        manager = _manager;
    }

    /**
     * @notice Receives a donated amount of base tokens to be added to the entity's balance.
     * @param _amount Amount donated in base token.
     * @dev Reverts if the donation fee percentage is larger than 100% (equal to 1e4 when represented as a zoc).
     * @dev Reverts if the entity is inactive or if the token transfer fails.
     */
    function donate(uint256 _amount) external {
        if (!registry.isActiveEntity(this)) revert EntityInactive();
        uint256 _fee;
        uint256 _netAmount;
        uint256 _feeMultiplier = registry.getDonationFee(this);
        if (_feeMultiplier > Math.ZOC) revert InvalidAction();
        unchecked {
            // unchecked as no possibility of overflow with baseToken precision
            _fee = _amount.zocmul(_feeMultiplier);
            // unchecked as the _feeMultiplier check with revert above protects against overflow
            _netAmount = _amount - _fee;
        }

        baseToken.safeTransferFrom(msg.sender, registry.treasury(), _fee);
        baseToken.safeTransferFrom(msg.sender, address(this), _netAmount);

        unchecked {
            // unchecked as no possibility of overflow with baseToken precision
            balance += _netAmount;
        }
    }

    /**
     * @notice Transfers an amount of base tokens from this entity to another entity.
     * @param _to The entity to receive the tokens.
     * @param _amount Contains the amount being donated (denominated in the base token's units).
     * @dev Reverts if the entity is inactive or if the token transfer fails.
     * @dev Reverts if the transfer fee percentage is larger than 100% (equal to 1e4 when represented as a zoc).
     * @dev Reverts with `Unauthorized` if the `msg.sender` is not the entity manager or a privileged role.
     */
    function transfer(Entity _to, uint256 _amount) requiresManager external {
        if (!registry.isActiveEntity(this)) revert EntityInactive();
        if (balance < _amount) revert InsufficientFunds();
        uint256 _fee;
        uint256 _netAmount;
        uint256 _feeMultiplier = registry.getTransferFee(this, _to);
        if (_feeMultiplier > Math.ZOC) revert InvalidAction();
        unchecked {
            // unchecked as no possibility of underflow with baseToken precision
            _fee = _amount.zocmul(_feeMultiplier);
            // unchecked as the _feeMultiplier check with revert above protects against overflow
            _netAmount = _amount - _fee;
        }

        baseToken.safeTransferFrom(msg.sender, registry.treasury(), _fee);
        baseToken.safeTransfer(address(_to), _netAmount);

        unchecked {
            // unchecked as no possibility of overflow with baseToken precision
            balance -= _amount;
        }
    }

    /**
     * @dev We override Auth.sol:isAuthorized() in order to achieve the following:
     * - Instead of asking this Entity about roles and such, ask the Registry.
     *   - Reason: We want to manage all permissions in one place -- on the Registry.
     * - Instead of passing `address(this)` to `auth.canCall`, we pass `address(bytes20("entity"))`
     *   - Reason: We are meeting the requirement to scope permissions across all Entities together.
     * - Instead of asking this Entity about its Auth `owner`, we ask the Registry.
     *   - Reason: We want to manage `owner` in one place -- on the Registry.
     */
    function isAuthorized(address user, bytes4 functionSig) internal view override returns (bool) {
        // Instead of asking this Entity about roles and capabilities, ask the Registry.
        Authority auth = registry.authority();

        // We make a couple small modifications to reframe auth in terms of Registry.
        return (address(auth) != address(0) && auth.canCall(user, address(bytes20("entity")), functionSig)) || user == registry.owner();
    }

}
