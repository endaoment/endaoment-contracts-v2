//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { ERC20Votes } from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { ERC20Permit } from "openzeppelin-contracts/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

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

    /// @notice Thrown when a caller attempts a transfer related ERC20 method.
    error TransferDisallowed();

    /// @notice Thrown when an unlock request cannot be processed.
    error InvalidUnlockRequest();

    /// @notice Emitted when a user vote locks NDAO for NVT.
    event Locked(address indexed holder, uint256 indexed depositIndex, uint256 amount);

    /// @notice Emitted when a user unlocks NVT for NDAO.
    event Unlocked(address indexed holder, uint256 indexed depositIndex, uint256 amount);
}

/**
 * @notice The NDAO Voting Token, an ERC20. It is minted by locking NDAO tokens, and unlocks in a stream
 * over time back to the user.
 */
contract NVT is NVTTypes, ERC20Votes {

    // --- Storage Variables ---

    /// @notice The total time over which a locked deposit of NDAO becomes unlocked to the user linearly.
    uint256 public constant STREAM_TIME = 365 days;

    /// @notice The NDAO Token address.
    INDAO public immutable ndao;

    /// @notice A mapping of NVT holders to their deposits of NDAO that have been locked.
    mapping(address => Deposit[]) deposits;

    // --- Constructor ---

    /**
     * @param _ndao The address of the NDAO Token contract.
     */
    constructor(INDAO _ndao) ERC20("NDAO Voting Token", "NVT") ERC20Permit("NVT") {
        ndao = _ndao;
    }

    // --- On-chain View Methods ---

    /**
     * @notice Calculates the how much NVT can be unlocked for NDAO for a given holder and deposit, at
     * the given timestamp.
     * @param _holder The address of the NVT token holder.
     * @param _index The index of deposit to interrogate.
     * @param _timestamp The unix timestamp at which the available NDAO will be calculated.
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
     */
    function getDeposit(address _holder, uint256 _index) external view returns (Deposit memory) {
        return deposits[_holder][_index];
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
