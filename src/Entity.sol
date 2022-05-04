//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

import { Registry } from  "./Registry.sol";
import { EndaomentAuth } from "./lib/auth/EndaomentAuth.sol";
import { Portfolio } from "./Portfolio.sol";
import { Math } from "./lib/Math.sol";

error EntityInactive();
error PortfolioInactive();
error InsufficientFunds();
error InvalidAction();
error InvalidTransferAttempt();

/**
 * @notice Entity contract inherited by Org and Fund contracts (and all future kinds of Entities).
 */
abstract contract Entity is EndaomentAuth {
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

    /// @notice Emitted when a donation is made.
    event EntityDonationReceived(address indexed from, address indexed to, uint256 amountReceived, uint256 amountFee);

    /// @notice Emitted when a transfer is made between entities.
    event EntityFundsTransferred(address indexed from, address indexed to, uint256 amountReceived, uint256 amountFee);

    /// @notice Emitted when a basetoken reconciliation completes
    event EntityBalanceReconciled(address indexed entity, uint256 amountReceived, uint256 amountFee);

    /// @notice Emitted when a portfolio deposit is made.
    event EntityDeposit(address indexed portfolio, uint256 baseTokenDeposited, uint256 sharesRecieved);

    /// @notice Emitted when a portfolio share redemption is made.
    event EntityRedeem(address indexed portfolio, uint256 sharesRedeemed, uint256 baseTokenReceived);

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
    constructor(
        Registry _registry,
        address _manager
    ) EndaomentAuth(
            _registry,
            bytes20(bytes.concat("entity", bytes1(entityType())))
    ) {
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
     * @notice Receives a donated amount of base tokens to be added to the entity's balance. Transfers default fee to treasury.
     * @param _amount Amount donated in base token.
     * @dev Reverts if the donation fee percentage is larger than 100% (equal to 1e4 when represented as a zoc).
     * @dev Reverts if the entity is inactive or if the token transfer fails.
     */
    function donate(uint256 _amount) external {
        uint32 _feeMultiplier = registry.getDonationFee(this);
        _donateWithFeeMultiplier(_amount, _feeMultiplier);
    }

    /**
     * @notice Receives a donated amount of base tokens to be added to the entity's balance. Transfers default or overridden fee to treasury.
     * @param _amount Amount donated in base token.
     * @dev Reverts if the donation fee percentage is larger than 100% (equal to 1e4 when represented as a zoc).
     * @dev Reverts if the entity is inactive or if the token transfer fails.
     */
    function donateWithOverrides(uint256 _amount) external {
        uint32 _feeMultiplier = registry.getDonationFeeWithOverrides(this);
        _donateWithFeeMultiplier(_amount, _feeMultiplier);
    }

    /**
     * @notice Receives a donated amount of base tokens to be added to the entity's balance. Transfers fee calculated by fee multiplier to treasury.
     * @param _amount Amount donated in base token.
     * @param _feeMultiplier Value indicating the percentage of the Endaoment donation fee to go to the Endaoment treasury.
     * @dev Reverts if the donation fee percentage is larger than 100% (equal to 1e4 when represented as a zoc).
     * @dev Reverts if the entity is inactive or if the token transfer fails.
     */
    function _donateWithFeeMultiplier(uint256 _amount, uint32 _feeMultiplier) internal {
        if (!registry.isActiveEntity(this)) revert EntityInactive();
        uint256 _fee;
        uint256 _netAmount;
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
        emit EntityDonationReceived(msg.sender, address(this), _amount, _fee);
    }

    /**
     * @notice Transfers an amount of base tokens from one entity to another. Transfers default fee to treasury.
     * @param _to The entity to receive the tokens.
     * @param _amount Contains the amount being donated (denominated in the base token's units).
     * @dev Reverts if the entity is inactive or if the token transfer fails.
     * @dev Reverts if the transfer fee percentage is larger than 100% (equal to 1e4 when represented as a zoc).
     * @dev Reverts with `Unauthorized` if the `msg.sender` is not the entity manager or a privileged role.
     */
    function transfer(Entity _to, uint256 _amount) requiresManager external {
        uint32 _feeMultiplier = registry.getTransferFee(this, _to);
        _transferWithFeeMultiplier(_to, _amount, _feeMultiplier);
    }

    /**
     * @notice Transfers an amount of base tokens from one entity to another. Transfers default or overridden fee to treasury.
     * @param _to The entity to receive the tokens.
     * @param _amount Contains the amount being donated (denominated in the base token's units).
     * @dev Reverts if the entity is inactive or if the token transfer fails.
     * @dev Reverts if the transfer fee percentage is larger than 100% (equal to 1e4 when represented as a zoc).
     * @dev Reverts with `Unauthorized` if the `msg.sender` is not the entity manager or a privileged role.
     */
    function transferWithOverrides(Entity _to, uint256 _amount) requiresManager external {
        uint32 _feeMultiplier = registry.getTransferFeeWithOverrides(this, _to);
        _transferWithFeeMultiplier(_to, _amount, _feeMultiplier);
    }

    /**
     * @notice Transfers an amount of base tokens from one entity to another. Transfers fee calculated by fee multiplier to treasury.
     * @param _to The entity to receive the tokens.
     * @param _amount Contains the amount being donated (denominated in the base token's units).
     * @param _feeMultiplier Value indicating the percentage of the Endaoment donation fee to go to the Endaoment treasury.
     * @dev Reverts if the entity is inactive or if the token transfer fails.
     * @dev Reverts if the transfer fee percentage is larger than 100% (equal to 1e4 when represented as a zoc).
     * @dev Reverts with `Unauthorized` if the `msg.sender` is not the entity manager or a privileged role.
     */
    function _transferWithFeeMultiplier(Entity _to, uint256 _amount, uint32 _feeMultiplier) internal {
        if (!registry.isActiveEntity(this)) revert EntityInactive();
        if (balance < _amount) revert InsufficientFunds();
        uint256 _fee;
        uint256 _netAmount;
        if (_feeMultiplier > Math.ZOC) revert InvalidAction();
        unchecked {
            // unchecked as no possibility of underflow with baseToken precision
            _fee = _amount.zocmul(_feeMultiplier);
            // unchecked as the _feeMultiplier check with revert above protects against overflow
            _netAmount = _amount - _fee;
        }
        baseToken.safeTransfer(registry.treasury(), _fee);
        baseToken.safeTransfer(address(_to), _netAmount);

        unchecked {
            // unchecked as no possibility of overflow with baseToken precision
            balance -= _amount;
            _to.receiveTransfer(_netAmount);
        }
        emit EntityFundsTransferred(address(this), address(_to), _amount, _fee);
    }

    /**
     * @notice Updates the receiving entity balance on a transfer, after verifying that the receiver's ERC20 balance has increased appropriately.
     * @param _transferAmount The amount being received on the transfer.
     * @dev This function is public, but is restricted such that it can only be called by other entities.
     */
     function receiveTransfer(uint256 _transferAmount) public {
         if (!registry.isActiveEntity(Entity(msg.sender))) revert InvalidTransferAttempt();
         balance += _transferAmount;
     }

     /**
     * @notice Deposits an amount of Entity's `baseToken` into an Endaoment-approved Portfolio.
     * @param _portfolio An Endaoment-approved portfolio.
     * @param _amount Amount of `baseToken` to deposit into the portfolio.
     * @param _data Data required by a portfolio to deposit.
     * @return _shares Amount of portfolio share tokens Entity received as a result of this deposit.
     */
    function portfolioDeposit(Portfolio _portfolio, uint256 _amount, bytes calldata _data) external requiresManager returns (uint256) {
        if(!registry.isActivePortfolio(_portfolio)) revert PortfolioInactive();
        balance -= _amount;
        baseToken.safeApprove(address(_portfolio), 0);
        baseToken.safeApprove(address(_portfolio), _amount);
        uint256 _shares = _portfolio.deposit(_amount, _data);
        emit EntityDeposit(address(_portfolio), _amount, _shares);
        return _shares;
    }

    /**
     * @notice Redeems an amount of Entity's portfolio shares for an amount of `baseToken`.
     * @param _portfolio An Endaoment-approved portfolio.
     * @param _shares Amount of share tokens to redeem.
     * @param _data Data required by a portfolio to redeem.
     * @return _received Amount of `baseToken` Entity received as a result of this redemption.
     */
    function portfolioRedeem(Portfolio _portfolio, uint256 _shares, bytes calldata _data) external requiresManager returns (uint256) {
        if(!registry.isActivePortfolio(_portfolio)) revert PortfolioInactive();
        uint256 _received = _portfolio.redeem(_shares, _data);
        // unchecked: a realistic balance can never overflow a uint256
        unchecked {
            balance += _received;
        }
        emit EntityDeposit(address(_portfolio), _shares, _received);
        return _received;
    }

    /**
     * @notice This sweeper method should be called to process amounts of baseToken that arrived at this Entity through methods
     * besides Entity:donate or Entity:transfer. For example, if this Entity receives a normal ERC20 transfer of baseToken, the
     * amount received will be unavailable for Entity use until this method is called to adjust the balance and process fees.
     */
    function reconcileBalance() external requiresManager {
        uint256 _sweepAmount = registry.baseToken().balanceOf(address(this)) - balance;
        uint256 _fee;
        uint256 _netAmount;
        if (_sweepAmount > 0) {
            uint32 _feeMultiplier = registry.getDonationFeeWithOverrides(this);
            if (_feeMultiplier > Math.ZOC) revert InvalidAction();
            unchecked {
                // unchecked as no possibility of overflow with baseToken precision
                _fee = _sweepAmount.zocmul(_feeMultiplier);
                // unchecked as the _feeMultiplier check with revert above protects against overflow
                _netAmount = _sweepAmount - _fee;
            }

            baseToken.safeTransfer(registry.treasury(), _fee);
            balance += _netAmount;
        }
        emit EntityBalanceReconciled(address(this), _sweepAmount, _fee);
    }
}
