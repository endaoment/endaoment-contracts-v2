// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.13;

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { MerkleProof } from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import { EndaomentAuth } from "./lib/auth/EndaomentAuth.sol";
import { RolesAuthority } from "./lib/auth/authorities/RolesAuthority.sol";

/**
 * @notice Defines the data, error, and event types used by the RollingMerkleDistributor contract.
 */
abstract contract RollingMerkleDistributorTypes {

    /// @notice Data associated with a proof-based claim.
    struct Claim {
        uint256 index; // Position of the claim in the list of the Merkle tree's leaf nodes.
        address claimant; // The account making the claim.
        uint256 amount; // The amount the claimant is owed.
        bytes32[] merkleProof; // The Merkle proof data.
    }

    /// @notice Emitted when an authorized account rolls over the Merkle root and claim window. Also emitted on
    /// deploy with initial root and claim window.
    event MerkleRootRolledOver(bytes32 indexed merkleRoot, uint256 windowEnd);

    /// @notice Updated when an account completes a proof based claim.
    event Claimed(uint256 indexed window, uint256 index, address indexed claimant, uint256 amount);

    /// @notice Thrown if  there is an attempt to rollover while the current claim window is still open.
    error PriorWindowStillOpen();

    /// @notice Thrown if there is an attempt to define a claim window period that is 0 seconds, or too long.
    error InvalidPeriod();

    /// @notice Thrown if a claimant attempts to claim funds that were already claimed.
    error AlreadyClaimed();

    /// @notice Thrown if the claimant provides an invalid Merkle proof when attempting to claim.
    error InvalidProof();

    /// @notice Thrown if a claim is attempted after the claim window has closed, but before its rolled over.
    error OutsideClaimWindow();
}

/**
 * @notice A rolling Merkle distributor. At the end of ever claim window, a privileged account can deploy
 * a new root (and window) to distribute more funds. The stakeholder must also supply the funds to be distributed by
 * the contract in a separate transaction. The intention is for the stakeholder to rollover unclaimed funds from the
 * previous window into the next Merkle root, so users can claim anytime and never "miss" their chance to do so. This
 * is an entirely trust based process. Privileged accounts can leave a user's fund out of the root, or deploy a root that
 * allows them alone to reclaim all the funds. This is by design.
 * @dev Based on the
 * [Uniswap merkle distributor](https://github.com/Uniswap/merkle-distributor/blob/master/contracts/MerkleDistributor.sol).
 */
contract RollingMerkleDistributor is RollingMerkleDistributorTypes, EndaomentAuth {

    /// @notice The ERC20 token that will be distributed by this contract.
    IERC20 public immutable token;

    /// @notice The current Merkle root which claimants must provide a proof against.
    bytes32 public merkleRoot;

    /// @notice A Unix timestamp denoting the last second of the current claim window.
    uint256 public windowEnd;

    /// @notice The maximum length of a claim window that can be defined at rollover. Does *not* apply to the
    /// length of the claim window for initial distribution, defined at deployment.
    uint256 public constant MAX_PERIOD = 30 days;

    /// @dev A mapping of claim windowEnd timestamps to a packed array of boolean flags denoting whether a given
    // leaf node in that window's Merkle tree has been claimed.
    mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMap;

    /**
     * @param _token The ERC20 token that will be distributed by this contract. This token *must* revert on
     * failed transfers.
     * @param _initialRoot The Merkle root for the initial distribution.
     * @param _initialPeriod The length of time, in seconds, of the initial claim window.
     * @param _authority The address of the authority which defines permissions for rollovers.
     */
    constructor(
        IERC20 _token,
        bytes32 _initialRoot,
        uint256 _initialPeriod,
        RolesAuthority _authority
    ) {
        token = _token;

        merkleRoot = _initialRoot;
        windowEnd = block.timestamp + _initialPeriod;

        initialize(_authority, "");

        emit MerkleRootRolledOver(merkleRoot, windowEnd);
    }

    /**
     * @notice Privileged method that sets a new Merkle root and defines a new claim window. Can only be called after
     * the previous window has closed.
     * @param _newRoot The new Merkle root for this distribution.
     * @param _period The length of the new claim window in seconds. Must be less than MAX_PERIOD.
     */
    function rollover(bytes32 _newRoot, uint256 _period) external requiresAuth {
        if (windowEnd >= block.timestamp) revert PriorWindowStillOpen();
        if (_period == 0 || _period > MAX_PERIOD) revert InvalidPeriod();

        merkleRoot = _newRoot;
        unchecked {
            // Check against MAX_PERIOD protects from overflow.
            windowEnd = block.timestamp + _period;
        }

        emit MerkleRootRolledOver(merkleRoot , windowEnd);
    }

    /**
     * @notice Helper method that reads from the boolean flag array and returns whether the Merkle tree leaf
     * node at a given index, for a given claim distribution window, has already been claimed.
     * @param _window The Unix timestamp of the end date of the claim window for which claim status is being queried.
     * @param _index The position of the claim in the list of the Merkle tree's leaf nodes.
     * @return _isClaimed The claim status for this node and this claim window.
     */
    function isClaimed(uint256 _window, uint256 _index) public view returns (bool) {
        uint256 _claimedWordIndex = _index / 256;
        uint256 _claimedBitIndex = _index % 256;
        uint256 _claimedWord = claimedBitMap[_window][_claimedWordIndex];
        uint256 _mask = (1 << _claimedBitIndex);
        return _claimedWord & _mask == _mask;
    }

    /**
     * @dev Internal helper method that writes to the bool array that a given leaf node from the
     * the Merkle root, for a given claim window, has been claimed.
     */
    function _setClaimed(uint256 _window, uint256 _index) private {
        uint256 _claimedWordIndex = _index / 256;
        uint256 _claimedBitIndex = _index % 256;
        claimedBitMap[_window][_claimedWordIndex] = claimedBitMap[_window][_claimedWordIndex] | (1 << _claimedBitIndex);
    }

    /**
     * @notice Method called by claimant to receive funds owed to them.
     * @param _claim The data for this claim. See `Claim` for more info.
     */
    function claim(Claim calldata _claim) external {
        if (block.timestamp > windowEnd) revert OutsideClaimWindow();

        uint256 _index = _claim.index;
        address _claimant = _claim.claimant;
        uint256 _amount = _claim.amount;
        bytes32[] calldata _merkleProof = _claim.merkleProof;

        if (isClaimed(windowEnd, _index)) revert AlreadyClaimed();

        // Verify the merkle proof.
        bytes32 _node = keccak256(abi.encodePacked(_index, _claimant, _amount));
        if (!MerkleProof.verify(_merkleProof, merkleRoot, _node)) revert InvalidProof();

        // Mark it claimed and send the token.
        _setClaimed(windowEnd, _index);
        // We know the token will be NDAO or USDC, and that those revert if the transfer fails,
        // so we rely on that behavior.
        token.transfer(_claimant, _amount);

        emit Claimed(windowEnd, _index, _claimant, _amount);
    }
}
