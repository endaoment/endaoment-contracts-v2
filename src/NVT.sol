//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { ERC20Votes } from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { ERC20Permit } from "openzeppelin-contracts/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { EndaomentAuth } from "./lib/auth/EndaomentAuth.sol";
import { RolesAuthority } from "./lib/auth/authorities/RolesAuthority.sol";

/**
 * @notice Subset of the ERC20 interface used for NVT's reference to the NDAO token.
 */
interface INDAO {
    /// @dev see IERC20
    function transfer(address to, uint256 amount) external returns (bool);
    /// @dev see IERC20
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @notice Defines the data, error, and event types used by the NVT token contract.
 */
abstract contract NVTTypes {

    /// @notice Data associated with an NDAO deposit that has been vote locked for NVT.
    struct Deposit {
        uint256 date; // Unix timestamp of when the deposit was made.
        uint256 amount; // The amount of NDAO initially deposited.
        uint256 balance; // The balance of NDAO that has not yet been unlocked by the user.
    }

    /// @notice Data associated with a request to unlock NVT and reclaim NDAO.
    struct UnlockRequest {
        uint256 index; // The deposit index being unlocked.
        uint256 amount; // The amount of NDAO to be unlocked.
    }

    /// @notice Data associated with an accounts vesting token distribution.
    struct VestingSchedule {
        uint256 startDate; // Unix timestamp of when the vesting started.
        uint256 vestDate; // Unix timestamp of when fully vested.
        uint256 amount; // Amount of tokens originally locked for vesting.
        uint256 balance; // The balance of tokens (vested & unvested) that have not yet been claimed by the vestee.
        bool wasClawedBack; // Flag denoting if this vesting distribution was clawed back.
    }

    /// @notice Thrown when a caller attempts a transfer related ERC20 method.
    error TransferDisallowed();

    /// @notice Thrown when an unlock request cannot be processed.
    error InvalidUnlockRequest();

    /// @notice Thrown if a 0-length vesting period is specified.
    error InvalidVestingPeriod();

    /// @notice Thrown if a vest lock is attempted for an existing vestee.
    error AccountAlreadyVesting();

    /// @notice Emitted when a user vote locks NDAO for NVT.
    event Locked(address indexed holder, uint256 indexed depositIndex, uint256 amount);

    /// @notice Emitted when a user unlocks NVT for NDAO.
    event Unlocked(address indexed holder, uint256 indexed depositIndex, uint256 amount);

    /// @notice Emitted when tokens are locked for vesting to a vestee.
    event VestLocked(address indexed vestee, uint256 amount, uint256 period);

    /// @notice Emitted when a vestee unlocks vested NVT tokens for NDAO.
    event VestUnlocked(address indexed vestee, uint256 amount);

    /// @notice Emitted when an authorized account reclaims tokens that have not yet vested to a vestee.
    event ClawedBack(address indexed vestee, uint256 amount);
}

/**
 * @notice The NDAO Voting Token, an ERC20. It is minted by locking NDAO tokens, and unlocks in a stream
 * over time back to the user.
 */
contract NVT is NVTTypes, ERC20Votes, EndaomentAuth {

    // --- Storage Variables ---

    /// @notice The total time over which a locked deposit of NDAO becomes unlocked to the user linearly.
    uint256 public constant STREAM_TIME = 365 days;

    /// @notice The NDAO Token address.
    INDAO public immutable ndao;

    /// @notice A mapping of NVT holders to their deposits of NDAO that have been vote locked.
    mapping(address => Deposit[]) deposits;

    /// @notice A mapping of vesting NVT holders to their vesting schedules.
    mapping(address => VestingSchedule) vestingSchedules;

    // --- Constructor ---

    /**
     * @param _ndao The address of the NDAO Token contract.
     * @param _authority The address of the authority which defines permissions for vests & clawbacks.
     */
    constructor(
        INDAO _ndao,
        RolesAuthority _authority
    ) ERC20("NDAO Voting Token", "NVT") ERC20Permit("NVT") EndaomentAuth(_authority, "") {
        ndao = _ndao;
    }

    // --- On-chain View Methods ---

    /**
     * @notice Calculates the how much NVT can be unlocked for NDAO for a given holder and deposit, at
     * the given timestamp.
     * @param _holder The address of the NVT token holder.
     * @param _index The index of deposit to interrogate.
     * @param _timestamp The Unix timestamp at which the available NDAO will be calculated.
     * @return _available The amount of NVT that can be unlocked for NDAO.
     */
    function availableForWithdrawal(
        address _holder,
        uint256 _index,
        uint256 _timestamp
    ) public view returns (uint256) {
        Deposit memory _deposit = deposits[_holder][_index];

        uint256 _elapsed;
        unchecked {
            // Since deposit date is the recorded block timestamp, this cannot overflow unless
            // the caller passes a date in the past. In `_unlock`, we pass the block.timestamp
            // when calling this method, so it should always be safe.
            _elapsed = _timestamp - _deposit.date;
        }

        if (_elapsed >= STREAM_TIME) {
            return _deposit.balance;
        }

        uint256 _totalStreamed = (_elapsed * _deposit.amount) / STREAM_TIME;

        uint256 _alreadyWithdrawn;
        uint256 _available;
        unchecked {
            // Deposit balance starts the same as its amount can only be decremented.
            _alreadyWithdrawn = _deposit.amount - _deposit.balance;
            // Implied invariant: the user has not already withdrawn more than is currently available to withdraw.
            _available = _totalStreamed - _alreadyWithdrawn;
        }

        return _available;
    }

    /**
     * @notice Calculate how much vested NVT can be vest unlocked for NDAO for a given vestee, at the given timestamp.
     * @param _vestee The account of the vesting NVT token holder.
     * @param _timestamp The unix timestamp at which the available NDAO will be calculated.
     * @return _available The amount of NDAO available for this vestee to unlock at this timestamp.
     */
    function availableForVestUnlock(address _vestee, uint256 _timestamp) public view returns (uint256) {
        VestingSchedule memory _schedule = vestingSchedules[_vestee];

        // After a clawback, the only balance left is by definition already vested.
        if (_schedule.wasClawedBack) {
            return _schedule.balance;
        }

        uint256 _duration;
        uint256 _elapsed;

        unchecked {
            // In the vestLock method, the vest date is defined as the start date *plus* the period (i.e. duration).
            _duration = _schedule.vestDate - _schedule.startDate;

            // Since start date is the recorded block timestamp, this cannot overflow unless
            // the caller passes a date in the past. Internally, we always pass the block.timestamp
            // when calling this method, so it should always be safe.
            _elapsed = _timestamp - _schedule.startDate;
        }

        if (_elapsed > _duration) {
            return _schedule.balance;
        }

        uint256 _totalVested = (_elapsed * _schedule.amount) / _duration;

        unchecked {
            // Amount and balance start the same, and balance can only be decremented.
            uint256 _alreadyWithdrawn = _schedule.amount - _schedule.balance;
            // Implied invariant: the user has not already withdrawn more than they have vested.
            return _totalVested - _alreadyWithdrawn;
        }
    }

    // --- ERC-20 Overrides ---

     /// @dev We override this because NVT is non-transferable. Always reverts with TransferDisallowed.
    function transfer(address /* to */, uint256 /* amount */) public pure override returns (bool) {
        revert TransferDisallowed();
    }

     /// @dev We override this because NVT is non-transferable. Always reverts with TransferDisallowed.
    function transferFrom(
        address /* from */,
        address /* to */,
        uint256 /* amount */
    ) public pure override returns (bool) {
        revert TransferDisallowed();
    }

     /// @dev We override this to prevent users wasting gas. Always reverts with TransferDisallowed.
    function approve(address /* spender */, uint256 /* amount */) public pure override returns (bool) {
        revert TransferDisallowed();
    }

    /// @dev We override this to prevent users wasting gas. Always reverts with TransferDisallowed.
    function increaseAllowance(
        address /* spender */,
        uint256 /* addedValue */
    ) public pure override returns (bool) {
        revert TransferDisallowed();
    }

    /// @dev We override this to prevent users wasting gas. Always reverts with TransferDisallowed.
    function decreaseAllowance(
        address /* spender */,
        uint256 /* subtractedValue */
    ) public pure override returns (bool) {
        revert TransferDisallowed();
    }

    // --- External Methods ---

    /**
     * @notice Lock NDAO and receive NVT tokens 1:1.
     * @param _amount How many NDAO tokens to lock in exchange for NVT.
     * @dev This method records this deposit to "stream" the NDAO unlock, that is, to make the NDAO locked available
     * for unlock linearly over the course of the next year.
     */
    function voteLock(uint256 _amount) external {
        deposits[msg.sender].push(
            Deposit({
                date: block.timestamp,
                amount: _amount,
                balance: _amount
            })
        );

        _mint(msg.sender, _amount);
        ndao.transferFrom(msg.sender, address(this), _amount);

        unchecked {
            // Deposit length now guaranteed to be at least 1
            emit Locked(msg.sender, deposits[msg.sender].length - 1, _amount);
        }
    }

    /**
     * @notice Unlock NDAO from a list of `msg.sender`'s qualifying deposits.
     * @param _requests A list of unlock requests, specifying the deposit index and amount to unlock in each.
     */
    function unlock(UnlockRequest[] calldata _requests) external {
        for (uint256 i = 0; i < _requests.length; i++) {
            _unlock(_requests[i]);
        }
    }

    /**
     * @notice Lock vesting NDAO tokens for a vestee and grant them NVT. Authorized accounts only.
     * @param _vestee The account receiving the vesting distribution. Each account can only receive
     * one vesting distribution.
     * @param _amount The number of NDAO tokens to be converted to NVT and vested.
     * @param _period The length of time over which tokens vest in seconds. Must be > 0.
     */
    function vestLock(address _vestee, uint256 _amount, uint256 _period) public requiresAuth {
        if (_period == 0) revert InvalidVestingPeriod();
        if (vestingSchedules[_vestee].vestDate != 0) revert AccountAlreadyVesting();

        _mint(_vestee, _amount);
        vestingSchedules[_vestee] = VestingSchedule({
            startDate: block.timestamp,
            vestDate: block.timestamp + _period,
            amount: _amount,
            balance: _amount,
            wasClawedBack: false
        });
        ndao.transferFrom(msg.sender, address(this), _amount);

        emit VestLocked(_vestee, _amount, _period);
    }

    /**
     * @notice Unlocks NVT tokens which have vested to the caller for NDAO.
     * @param _amount The number of NDAO which will be unlocked by burning vested NVT.
     */
    function unlockVested(uint256 _amount) public {
        uint256 _available = availableForVestUnlock(msg.sender, block.timestamp);
        if (_amount > _available) revert InvalidUnlockRequest();

        _burn(msg.sender, _amount);
        unchecked {
            // The _available is less than or equal to balance, and _available is checked to be less than
            // _amount above, thus subtracting _amount from balance cannot overflow.
            vestingSchedules[msg.sender].balance -= _amount;
        }
        ndao.transfer(msg.sender, _amount);

        emit VestUnlocked(msg.sender, _amount);
    }

    /**
     * @notice Returns all unvested tokens to the authorized caller for a given vestee. Cannot clawback any vested 
     * tokens, whether they have been unlocked or not.
     * @param _vestee The vestee to claw back from.
     */
    function clawback(address _vestee) public requiresAuth {
        uint256 _vestedBalance = availableForVestUnlock(_vestee, block.timestamp);

        uint256 _unvestedBalance;
        unchecked {
            // Implied invariant: the vestee has not already withdrawn more than they have vested.
            _unvestedBalance = vestingSchedules[_vestee].balance - _vestedBalance;
            vestingSchedules[_vestee].balance -= _unvestedBalance;
        }

        vestingSchedules[_vestee].wasClawedBack = true;
        _burn(_vestee, _unvestedBalance);
        ndao.transfer(msg.sender, _unvestedBalance);

        emit ClawedBack(_vestee, _unvestedBalance);
    }

    // --- Internal Methods ---

    /// @dev Internal helper to process a single unlock request.
    function _unlock(UnlockRequest calldata _request) private {
        uint256 _available = availableForWithdrawal(msg.sender, _request.index, block.timestamp);
        if (_request.amount > _available) revert InvalidUnlockRequest();

        deposits[msg.sender][_request.index].balance -= _request.amount;

        _burn(msg.sender, _request.amount);
        ndao.transfer(msg.sender, _request.amount);

        emit Unlocked(msg.sender, _request.index, _request.amount);
    }

    // --- Off-chain 'Lens' Methods ---

    /**
     * @notice Helper method for accessing the number of deposits a holder has made.
     * @param _holder The address of the NVT token holder.
     * @return _length The number of deposits this holder has made.
     */
    function getNumDeposits(address _holder) external view returns (uint256) {
        return deposits[_holder].length;
    }

    /**
     * @notice Helper method for accessing deposit data externally.
     * @param _holder The address of the NVT token holder.
     * @param _index The index of the deposit to retrieve.
     * @return _deposit The deposit for this holder at a given index.
     */
    function getDeposit(address _holder, uint256 _index) external view returns (Deposit memory) {
        return deposits[_holder][_index];
    }

    /**
     * @notice Helper method for accessing vesting schedule data externally.
     * @param _vestee The account of the vesting NVT token holder.
     * @return _vestingSchedule The vesting schedule data for this vestee.
     */
    function getVestingSchedule(address _vestee) external view returns (VestingSchedule memory) {
        return vestingSchedules[_vestee];
    }

     /**
     * @notice Returns a list of all past deposit indices which still have a locked NDAO balance. This method is
     * intended only for off-chain use for the ease of integration. It is extremely inefficient.
     * @param _holder The NVT token holder.
     * @param _startIndex The first index to investigate for an active balance. The method will look at this deposit,
     * and all deposits made after it. To interrogate all active indices, set this to 0. Using zero works as long as
     * the node you are querying does not enforce an off-chain gas limit. If it does, chunk requests using this param.
     * @return _activeIndices A list of all deposit indices with a non-zero locked balance.
     */
    function getActiveDepositIndices(address _holder, uint256 _startIndex) public view returns (uint256[] memory) {
        uint256 _nextHolderIndex = deposits[_holder].length;

        if (_startIndex >= _nextHolderIndex) {
            return new uint256[](0);
        }

        uint256 _activeCount = 0;

        // Figure out how many active deposits there are.
        for (uint256 _index = _startIndex; _index < _nextHolderIndex; _index++) {
            if (deposits[_holder][_index].balance > 0) {
                _activeCount++;
            }
        }

        // Initialize the appropriately sized array.
        uint256[] memory _activeIndices = new uint256[](_activeCount);
        uint256 _accumulatorIndex = 0;

        // Do another pass populating the array with active indices.
        for (uint256 _index = _startIndex; _index < _nextHolderIndex; _index++) {
            if (deposits[_holder][_index].balance > 0) {
                _activeIndices[_accumulatorIndex] = _index;
                _accumulatorIndex++;
            }
        }

        return _activeIndices;
    }

    /**
     * @notice Helper method that sums the total NDAO available for unlocking across multiple deposits. This method is
     * intended only for off-chain use for the ease of integration. It is extremely inefficient.
     * @param _holder The NVT token holder.
     * @param _startIndex The first index to investigate for an active balance. The method will look at this deposit,
     * and all deposits made after it. To interrogate all active indices, set this to 0. Using zero works as long as
     * the node you are querying does not enforce an off-chain gas limit. If it does, chunk the requests using
     * this param.
     * @param _timestamp The unix timestamp at which the available NDAO will be calculated.
     * @return balance The sum of all NDAO tokens that are available to be unlocked across all deposits.
     */
    function getTotalAvailableForWithdrawal(
        address _holder,
        uint256 _startIndex,
        uint256 _timestamp
    ) external view returns (uint256) {
        uint256[] memory _activeIndices = getActiveDepositIndices(_holder, _startIndex);

        uint256 _totalAvailable = 0;

        for (uint256 _i = 0; _i < _activeIndices.length; _i++) {
            uint256 _index = _activeIndices[_i];
            _totalAvailable += availableForWithdrawal(_holder, _index, _timestamp);
        }

        return _totalAvailable;
    }
}
