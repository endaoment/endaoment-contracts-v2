//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { RollingMerkleDistributor, RollingMerkleDistributorTypes } from "./RollingMerkleDistributor.sol";
import { Entity } from "./Entity.sol";

/// @notice Wrapper contract to allow Orgs to claim and reconcile base token rewards in one transaction.
contract AtomicClaim {

    /**
     * @notice Simple wrapper method that allows anyone to make a base token rewards claim on behalf of an entity,
     * then perform a reconcile balance operation to include the claimed funds in the Entity's internal balance.
     * @param _entity The entity which has a claimable reward.
     * @param _distributor The Merkle distributor from which the rewards claim will be made.
     * @param _index The Merkle distributor claim index.
     * @param _amount The claimable amount in the Merkle distributor for the entity.
     * @param _merkleProof The claim proof for this entity, index, and amount.
     */
    function atomicClaimAndReconcile (
        Entity _entity,
        RollingMerkleDistributor _distributor,
        uint256 _index,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) public {
        _distributor.claim(RollingMerkleDistributorTypes.Claim({
            index: _index,
            claimant: address(_entity),
            amount: _amount,
            merkleProof: _merkleProof
        }));

        _entity.reconcileBalance();
    }
}