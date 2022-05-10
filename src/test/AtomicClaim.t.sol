// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { DeployTest } from "./utils/DeployTest.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { Merkle } from "murky/Merkle.sol";
import { AtomicClaim } from "../AtomicClaim.sol";
import { RollingMerkleDistributor, RollingMerkleDistributorTypes } from "../RollingMerkleDistributor.sol";
import { RollingMerkleDistributorTest } from "./RollingMerkleDistributor.t.sol";
import { Org } from "../Org.sol";

contract AtomicClaimTest is RollingMerkleDistributorTest {

    Org org;
    AtomicClaim atomicClaim;

    function setUp() public override {
        super.setUp();
        org = orgFundFactory.deployOrg("1234-5678", "5417");
        atomicClaim = new AtomicClaim();
    }

    function testFuzz_CanMakeAtomicClaimForOrg(
        address _sender,
        uint256 _amount,
        uint256 _seed
    ) public {
        _amount = bound(_amount, 0, MAX_AMOUNT);
        vm.warp(baseDistributor.windowEnd() + 1);

        // Generate Merkle data.
        (bytes32 _root, bytes32[] memory _proof, uint256 _index) = makeBigTree(address(org), _amount, _seed);

        vm.startPrank(board);
        // Fund the baseDistributor.
        baseToken.mint(address(baseDistributor), type(uint128).max);
        // Rollover the root.
        baseDistributor.rollover(_root, 7 days);
        // Enable Org donations with no fee.
        globalTestRegistry.setDefaultDonationFee(1, 0);
        vm.stopPrank();
        uint256 _window = baseDistributor.windowEnd();

        // Execute atomic claim.
        vm.prank(_sender);
        expectEvent_Claimed(_window, _index, address(org), _amount);
        atomicClaim.atomicClaimAndReconcile(org, baseDistributor, _index, _amount, _proof);

        // Validate internal and external balance are updated, claim is marked as complete on distributor.
        assertEq(org.balance(), _amount);
        assertEq(baseToken.balanceOf(address(org)), _amount);
        assertTrue(baseDistributor.isClaimed(_window, _index));
    }
}
