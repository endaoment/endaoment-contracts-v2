// SPDX-License-Identifier: BSD 3-Claused
pragma solidity 0.8.13;

import { DeployTest } from "./utils/DeployTest.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { Merkle } from "murky/Merkle.sol";
import { RollingMerkleDistributor, RollingMerkleDistributorTypes } from "../RollingMerkleDistributor.sol";

contract RollingMerkleDistributorTest is RollingMerkleDistributorTypes, DeployTest {
    Merkle merkle; // Used as lib for generating roots/proofs for tests.
    IERC20 token; // token is NDAO, just cast as IERC20 for convenience.

    // Shadows EndaomentAuth
    error Unauthorized();

    // Choose a value well above anything reasonable for bounding fuzzed distribution periods.
    uint256 MAX_FUZZ_PERIOD = 1000 * (365 days);

    address[] public actors = [board, tokenTrust];

    function setUp() public virtual override {
        super.setUp();
        token = IERC20(address(ndao));

        merkle = new Merkle();
        vm.label(address(merkle), "merkle");
    }

    function getAuthorizedActor(uint256 _seed) public returns (address) {
        uint256 _index = bound(_seed, 0, actors.length - 1);
        return actors[_index];
    }

    function jumpPastWindow() public {
        vm.warp(distributor.windowEnd() + 1);
    }

    function expectEvent_RolledOver(bytes32 _merkleRoot, uint256 _windowEnd) public {
        vm.expectEmit(true, true, true, true);
        emit MerkleRootRolledOver(_merkleRoot, _windowEnd);
    }

    function expectEvent_Claimed(uint256 _window, uint256 _index, address _claimant, uint256 _amount) public {
        vm.expectEmit(true, true, true, true);
        emit Claimed(_window, _index, _claimant, _amount);
    }

    // Makes a Merkle tree leaf node for the index, claimant, and amount provided.
    function makeNode(uint256 _index, address _claimant, uint256 _amount) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_index, _claimant, _amount));
    }

    uint256 MAX_TREE_SIZE = 10000; // 10,000 claimants
    uint256 MAX_AMOUNT = 1000000000 * 1e18; // 1 billion tokens

    // Make an address from two integers.
    function makeAddress(uint256 _a, uint256 _b) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(_a, _b)))));
    }

    // Takes some parameters and a seed and uses it to create a large pseudorandom Merkle tree with the
    // requested claimant and amount stuffed into somewhere. Returns the Merkle root, and the proof and
    // index for the claimant.
    function makeBigTree(
        address _claimant,
        uint256 _amount,
        uint256 _seed
    ) public returns (bytes32 _root, bytes32[] memory _proof, uint256 _claimantIndex) {
        uint256 _seedHash1 = uint256(keccak256(abi.encode(_seed)));
        uint256 _seedHash2 = uint256(keccak256(abi.encode(_seedHash1)));

        uint256 _treeSize = bound(_seed, 2, MAX_TREE_SIZE);
        _claimantIndex = bound(_seedHash1, 0, _treeSize - 1);
        bytes32[] memory _tree = new bytes32[](_treeSize);

        for (uint256 _index = 0; _index < _treeSize; _index++) {
            bytes32 _node;

            if (_index == _claimantIndex) {
                _node = makeNode(_index, _claimant, _amount);
            } else {
                _node = makeNode(
                    _index,
                    makeAddress(_index, _seed),
                    bound(_seedHash2, 0, MAX_AMOUNT)
                );
            }

            _tree[_index] = _node;
        }

        _root = merkle.getRoot(_tree);
        _proof = merkle.getProof(_tree, _claimantIndex);
    }
}

// Tests for deployment of the RollingMerkleDistributor.
contract Deployment is RollingMerkleDistributorTest {

    function test_Deployment() public {
        assertEq(address(distributor.authority()), address(globalTestRegistry));
        assertEq(address(distributor.token()), address(token));
        assertEq(distributor.merkleRoot(), initialRoot);
        assertEq(distributor.windowEnd(), block.timestamp + initialPeriod);

        assertEq(address(baseDistributor.authority()), address(globalTestRegistry));
        assertEq(address(baseDistributor.token()), address(baseToken));
        assertEq(baseDistributor.merkleRoot(), initialRoot);
        assertEq(baseDistributor.windowEnd(), block.timestamp + initialPeriod);
    }

    function testFuzz_Deployment(address _token, bytes32 _root, uint256 _period) public {
        _period = bound(_period, 1, MAX_FUZZ_PERIOD);

        expectEvent_RolledOver(_root, block.timestamp + _period);
        RollingMerkleDistributor _distributor = new RollingMerkleDistributor(IERC20(_token), _root, _period, globalTestRegistry);

        assertEq(address(_distributor.authority()), address(globalTestRegistry));
        assertEq(address(_distributor.token()), _token);
        assertEq(_distributor.merkleRoot(), _root);
        assertEq(_distributor.windowEnd(), block.timestamp + _period);
    }
}

// Tests the ability to rollover the merkle root and claim window.
contract Rollover is RollingMerkleDistributorTest {

    function testFuzz_NonAuthorizedCannotRollover(address _nonAdmin, bytes32 _root, uint256 _period) public {
        vm.assume(
            _nonAdmin != board &&
            _nonAdmin != capitalCommittee
        );
        _period = bound(_period, 1, MAX_FUZZ_PERIOD);

        vm.expectRevert(Unauthorized.selector);
        distributor.rollover(_root, _period);
    }

    function testFuzz_CannotRolloverDuringWindow(bytes32 _root, uint256 _period) public {
        _period = bound(_period, 1, MAX_FUZZ_PERIOD);

        vm.prank(board);
        vm.expectRevert(PriorWindowStillOpen.selector);
        distributor.rollover(_root, _period);
    }

    function testFuzz_CannotRolloverAtEndOfWindow(bytes32 _root, uint256 _period) public {
        _period = bound(_period, 1, MAX_FUZZ_PERIOD);
        vm.warp(distributor.windowEnd()); // Jump to last second of current window.

        vm.prank(board);
        vm.expectRevert(PriorWindowStillOpen.selector);
        distributor.rollover(_root, _period);
    }

    function testFuzz_CannotSetPeriodLengthToZero(bytes32 _root) public {
        jumpPastWindow();

        vm.prank(board);
        vm.expectRevert(InvalidPeriod.selector);
        distributor.rollover(_root, 0);
    }

    function testFuzz_CannotSetPeriodLongerThanMaxLength(bytes32 _root, uint256 _period) public {
        uint256 _max = distributor.MAX_PERIOD();
        _period = bound(_period, _max + 1, MAX_FUZZ_PERIOD);
        jumpPastWindow();

        vm.prank(board);
        vm.expectRevert(InvalidPeriod.selector);
        distributor.rollover(_root, _max + 1);
    }

    function testFuzz_CanRolloverTheWindow(bytes32 _root, uint256 _period, uint256 _seed) public {
        address _actor = getAuthorizedActor(_seed);
        uint256 _max = distributor.MAX_PERIOD();
        _period = bound(_period, 1, _max);
        jumpPastWindow();

        vm.prank(_actor);
        expectEvent_RolledOver(_root, block.timestamp + _period);
        distributor.rollover(_root, _period);

        uint256 _expectedWindow = block.timestamp + _period;

        assertEq(distributor.merkleRoot(), _root);
        assertEq(distributor.windowEnd(), _expectedWindow);
    }

    function testFuzz_CanRolloverTheBaseDistributorWindow(bytes32 _root, uint256 _period, uint256 _seed) public {
        address _actor = getAuthorizedActor(_seed);
        uint256 _max = baseDistributor.MAX_PERIOD();
        _period = bound(_period, 1, _max);
        vm.warp(baseDistributor.windowEnd() + 1);

        vm.prank(_actor);
        expectEvent_RolledOver(_root, block.timestamp + _period);
        baseDistributor.rollover(_root, _period);

        uint256 _expectedWindow = block.timestamp + _period;

        assertEq(baseDistributor.merkleRoot(), _root);
        assertEq(baseDistributor.windowEnd(), _expectedWindow);
    }
}

// Tests making claims from the Rolling Merkle Distributor.
contract Claim is RollingMerkleDistributorTest {

    function testFuzz_CannotClaimOutsideOfWindow(
        uint256 _index,
        address _claimant,
        uint256 _amount,
        bytes32 _data
    ) public {
        jumpPastWindow();

        bytes32[] memory _proof = new bytes32[](1);
        _proof[0] = _data;
        Claim memory _claim = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount,
            merkleProof: _proof
        });

        vm.expectRevert(OutsideClaimWindow.selector);
        distributor.claim(_claim);
    }

    function testFuzz_CanMakeTwoClaims(
        address _claimant1,
        uint256 _amount1,
        address _claimant2,
        uint256 _amount2
    ) public {
        vm.assume(
            _claimant1 != address(distributor) &&
            _claimant2 != address(distributor)
        );
        vm.assume(_claimant1 != _claimant2);
        _amount1 = bound(_amount1, 0, type(uint128).max);
        _amount2 = bound(_amount1, 0, type(uint128).max);

        // Fund the distributor.
        vm.prank(board);
        ndao.mint(address(distributor), _amount1 + _amount2);

        // Create the Merkle data.
        bytes32 _node1 = makeNode(0, _claimant1, _amount1);
        bytes32 _node2 = makeNode(1, _claimant2, _amount2);

        bytes32[] memory _tree = new bytes32[](2);
        _tree[0] = _node1;
        _tree[1] = _node2;

        bytes32 _root = merkle.getRoot(_tree);
        bytes32[] memory _proof1 = merkle.getProof(_tree, 0);
        bytes32[] memory _proof2 = merkle.getProof(_tree, 1);

        // Rollover the distributor root.
        jumpPastWindow();
        vm.prank(board);
        distributor.rollover(_root, 7 days);
        uint256 _window = distributor.windowEnd();

        // Make a claim 1
        Claim memory _claim1 = Claim({
            index: 0,
            claimant: _claimant1,
            amount: _amount1,
            merkleProof: _proof1
        });
        expectEvent_Claimed(_window, 0, _claimant1, _amount1);
        distributor.claim(_claim1);

        assertTrue(distributor.isClaimed(_window, 0));
        assertFalse(distributor.isClaimed(_window, 1));
        assertEq(ndao.balanceOf(_claimant1), _amount1);
        assertEq(ndao.balanceOf(address(distributor)), _amount2);

         // Make a claim 2
        Claim memory _claim2 = Claim({
            index: 1,
            claimant: _claimant2,
            amount: _amount2,
            merkleProof: _proof2
        });
        expectEvent_Claimed(_window, 1, _claimant2, _amount2);
        distributor.claim(_claim2);

        assertTrue(distributor.isClaimed(_window, 1));
        assertEq(ndao.balanceOf(_claimant2), _amount2);
        assertEq(ndao.balanceOf(address(distributor)), 0);
    }

    function testFuzz_CanMakeClaimWithBigTree(address _claimant, uint256 _amount, uint256 _seed) public {
        vm.assume(_claimant != address(distributor));
        _amount = bound(_amount, 0, MAX_AMOUNT);
        jumpPastWindow();

        // Generate Merkle data.
        (bytes32 _root, bytes32[] memory _proof, uint256 _index) = makeBigTree(_claimant, _amount, _seed);

        vm.startPrank(board);
        // Fund the distributor.
        ndao.mint(address(distributor), type(uint128).max);
        // Rollover the root.
        distributor.rollover(_root, 7 days);
        vm.stopPrank();
        uint256 _window = distributor.windowEnd();

        // Make a claim.
        Claim memory _claim = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount,
            merkleProof: _proof
        });
        expectEvent_Claimed(_window, _index, _claimant, _amount);
        distributor.claim(_claim);

        assertTrue(distributor.isClaimed(_window, _index));
        assertEq(ndao.balanceOf(_claimant), _amount);
    }

    function testFuzz_CanMakeClaimAgainstBaseDistributor(address _claimant, uint256 _amount, uint256 _seed) public {
        vm.assume(_claimant != address(baseDistributor));
        _amount = bound(_amount, 0, MAX_AMOUNT);
        vm.warp(baseDistributor.windowEnd() + 1);

        // Generate Merkle data.
        (bytes32 _root, bytes32[] memory _proof, uint256 _index) = makeBigTree(_claimant, _amount, _seed);

        vm.startPrank(board);
        // Fund the baseDistributor.
        baseToken.mint(address(baseDistributor), type(uint128).max);
        // Rollover the root.
        baseDistributor.rollover(_root, 7 days);
        vm.stopPrank();
        uint256 _window = baseDistributor.windowEnd();

        // Make a claim.
        Claim memory _claim = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount,
            merkleProof: _proof
        });
        expectEvent_Claimed(_window, _index, _claimant, _amount);
        baseDistributor.claim(_claim);

        assertTrue(baseDistributor.isClaimed(_window, _index));
        assertEq(baseToken.balanceOf(_claimant), _amount);
    }

    function testFuzz_CanMakeClaimAtTheEndOfTheWindow(address _claimant, uint256 _amount, uint256 _seed) public {
        vm.assume(_claimant != address(distributor));
        _amount = bound(_amount, 0, MAX_AMOUNT);

        jumpPastWindow();

        // Generate Merkle data.
        (bytes32 _root, bytes32[] memory _proof, uint256 _index) = makeBigTree(_claimant, _amount, _seed);

        vm.startPrank(board);
        // Fund the distributor.
        ndao.mint(address(distributor), type(uint128).max);
        // Rollover the root.
        distributor.rollover(_root, 7 days);
        vm.stopPrank();

        uint256 _window = distributor.windowEnd();
        vm.warp(_window); // jump to the exact second the window ends

        // Make a claim.
        Claim memory _claim = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount,
            merkleProof: _proof
        });
        expectEvent_Claimed(_window, _index, _claimant, _amount);
        distributor.claim(_claim);

        assertTrue(distributor.isClaimed(_window, _index));
        assertEq(ndao.balanceOf(_claimant), _amount);
    }

    function testFuzz_AllowsSecondClaimInNewWindow(
        address _claimant,
        uint256 _amount1,
        uint256 _amount2,
        uint256 _seed1,
        uint256 _seed2
    ) public {
        vm.assume(_claimant != address(distributor));
        _amount1 = bound(_amount1, 0, MAX_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_AMOUNT);
        jumpPastWindow();

        // Generate Merkle data.
        (bytes32 _root, bytes32[] memory _proof, uint256 _index) = makeBigTree(_claimant, _amount1, _seed1);

        vm.startPrank(board);
        // Fund the distributor.
        ndao.mint(address(distributor), type(uint128).max);
        // Rollover the root.
        distributor.rollover(_root, 7 days);
        vm.stopPrank();
        uint256 _window = distributor.windowEnd();

        // Make a claim.
        Claim memory _claim1 = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount1,
            merkleProof: _proof
        });
        distributor.claim(_claim1);

        assertTrue(distributor.isClaimed(_window, _index));
        assertEq(ndao.balanceOf(_claimant), _amount1);

        // Generate new Merkle data and rollover again.
        (_root, _proof, _index) = makeBigTree(_claimant, _amount2, _seed2);
        jumpPastWindow();
        vm.prank(board);
        distributor.rollover(_root, 7 days);
        _window = distributor.windowEnd();

        // Make another claim.
         Claim memory _claim2 = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount2,
            merkleProof: _proof
        });
        vm.prank(_claimant);
        expectEvent_Claimed(_window, _index, _claimant, _amount2);
        distributor.claim(_claim2);

        assertTrue(distributor.isClaimed(_window, _index));
        assertEq(ndao.balanceOf(_claimant), _amount1 + _amount2);
    }

    function testFuzz_CanNotMakeSecondClaimInSameWindow(address _claimant, uint256 _amount, uint256 _seed) public {
        vm.assume(_claimant != address(distributor));
        _amount = bound(_amount, 0, MAX_AMOUNT);
        jumpPastWindow();

        // Generate Merkle data.
        (bytes32 _root, bytes32[] memory _proof, uint256 _index) = makeBigTree(_claimant, _amount, _seed);

        vm.startPrank(board);
        // Fund the distributor.
        ndao.mint(address(distributor), type(uint128).max);
        // Rollover the root.
        distributor.rollover(_root, 7 days);
        vm.stopPrank();
        uint256 _window = distributor.windowEnd();

        // Make a claim.
        Claim memory _claim = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount,
            merkleProof: _proof
        });
        distributor.claim(_claim);

        assertTrue(distributor.isClaimed(_window, _index));
        assertEq(ndao.balanceOf(_claimant), _amount);

        // Attempt to make the same claim.
        vm.expectRevert(AlreadyClaimed.selector);
        distributor.claim(_claim);
    }

    function testFuzz_CanNotMakeClaimWithBadProofData(address _claimant, uint256 _amount, uint256 _seed) public {
        vm.assume(_claimant != address(distributor));
        _amount = bound(_amount, 0, MAX_AMOUNT);
        jumpPastWindow();

        // Generate Merkle data.
        (bytes32 _root, , uint256 _index) = makeBigTree(_claimant, _amount, _seed);
        bytes32[] memory _badProof = new bytes32[](1);
        _badProof[0] = keccak256(abi.encode(_seed));

        vm.startPrank(board);
        // Fund the distributor.
        ndao.mint(address(distributor), type(uint128).max);
        // Rollover the root.
        distributor.rollover(_root, 7 days);
        vm.stopPrank();

        // Make a claim.
        Claim memory _claim = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount,
            merkleProof: _badProof
        });
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(_claim);
    }

    function testFuzz_CanNotMakeClaimWithBadClaimData(address _claimant, uint256 _amount, uint256 _seed) public {
        vm.assume(_claimant != address(distributor));
        _amount = bound(_amount, 0, MAX_AMOUNT);
        jumpPastWindow();

        // Generate Merkle data.
        (bytes32 _root, bytes32[] memory _proof, uint256 _index) = makeBigTree(_claimant, _amount, _seed);

        vm.startPrank(board);
        // Fund the distributor.
        ndao.mint(address(distributor), type(uint128).max);
        // Rollover the root.
        distributor.rollover(_root, 7 days);
        vm.stopPrank();
        uint256 _window = distributor.windowEnd();

        // Make a claim with the wrong index.
        Claim memory _claim = Claim({
            index: _index + 1,
            claimant: _claimant,
            amount: _amount,
            merkleProof: _proof
        });
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(_claim);

        // Make a claim with the wrong claimant.
        _claim = Claim({
            index: _index,
            claimant: makeAddress(_index, _seed),
            amount: _amount,
            merkleProof: _proof
        });
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(_claim);

        // Make a claim with the wrong amount.
        _claim = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount + 1,
            merkleProof: _proof
        });
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(_claim);

        assertFalse(distributor.isClaimed(_window, _index));
    }

    function testFuzz_CanMakeAClaimFromAnInitialDeployment(address _claimant, uint256 _amount, uint256 _seed) public {
        vm.assume(
            _claimant != address(distributor) &&
            _claimant != board
        );
        _amount = bound(_amount, 0, MAX_AMOUNT);

        // Generate Merkle data.
        (bytes32 _root, bytes32[] memory _proof, uint256 _index) = makeBigTree(_claimant, _amount, _seed);

        // Deploy a new distributor.
        RollingMerkleDistributor _distributor = new RollingMerkleDistributor(token, _root, 7 days, globalTestRegistry);
        vm.assume(_claimant != address(_distributor));
        uint256 _window = _distributor.windowEnd();

        // Fund the distributor.
        vm.prank(board);
        ndao.mint(address(_distributor), type(uint128).max);

        // Make a claim.
        Claim memory _claim = Claim({
            index: _index,
            claimant: _claimant,
            amount: _amount,
            merkleProof: _proof
        });
        expectEvent_Claimed(_distributor.windowEnd(), _index, _claimant, _amount);
        _distributor.claim(_claim);

        assertTrue(_distributor.isClaimed(_window, _index));
        assertEq(ndao.balanceOf(_claimant), _amount);
    }
}
