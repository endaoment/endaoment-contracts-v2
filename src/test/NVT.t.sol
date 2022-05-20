// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { DeployTest } from "./utils/DeployTest.sol";
import { NVT, NVTTypes, INDAO } from "../NVT.sol";
import { NDAO } from "../NDAO.sol";

contract NVTTest is NVTTypes, DeployTest {
    // In the Solmate ERC20 implementation, attempting to transfer tokens you don't have reverts w/ an overflow panic
    bytes ErrorNoNdaoTokensError = abi.encodeWithSignature("Panic(uint256)", 0x11);

    // Shadows EndaomentAuth
    error Unauthorized();

    // uint140 is used in the struct for packing purposes.
    uint256 MAX_DEPOSIT_AMOUNT = type(uint104).max;
    uint256 MAX_VESTING_AMOUNT = type(uint96).max;

    // Using 32 bits for the vesting period means we can't vest longer than ~84 years.
    uint256 MAX_VESTING_PERIOD = 83 * (365 days);

    address[] public actors = [board, capitalCommittee];

    function getAuthorizedActor(uint256 _seed) public returns (address) {
        uint256 _index = bound(_seed, 0, actors.length - 1);
        return actors[_index];
    }

    function mintNdaoAndApproveNvt(address _holder, uint256 _amount) public {
        vm.assume(
            _holder != address(0) &&
            _holder != address(ndao) &&
            _holder != address(nvt)
        );

        vm.prank(board);
        ndao.mint(_holder, _amount);

        vm.prank(_holder);
        ndao.approve(address(nvt), type(uint256).max);
    }

    function mintNdaoAndVoteLock(address _holder, uint256 _amount) public {
        mintNdaoAndApproveNvt(_holder, _amount);
        vm.prank(_holder);
        nvt.voteLock(_amount);
    }

    function mintNdaoAndVest(address _vestee, uint256 _amount, uint256 _period) public {
        vm.assume(
            _vestee != board &&
            _vestee != capitalCommittee &&
            _vestee != address(0) &&
            _vestee != address(nvt)
        );
        mintNdaoAndApproveNvt(board, _amount);

        vm.prank(board);
        nvt.vestLock(_vestee, _amount, _period);
    }

    function expectEvent_Locked(address _holder, uint256 _depositIndex, uint256 _amount) public {
        vm.expectEmit(true, true, false, true);
        emit Locked(_holder, _depositIndex, _amount);
    }

    function expectEvent_Unlocked(address _holder, uint256 _depositIndex, uint256 _amount) public {
        vm.expectEmit(true, true, false, true);
        emit Unlocked(_holder, _depositIndex, _amount);
    }

    function expectEvent_VestLocked(address _vestee, uint256 _amount, uint256 _period) public {
        vm.expectEmit(true, false, false, true);
        emit VestLocked(_vestee, _amount, _period);
    }

    function expectEvent_VestUnlocked(address _vestee, uint256 _amount) public {
        vm.expectEmit(true, false, false, true);
        emit VestUnlocked(_vestee, _amount);
    }

    function expectEvent_ClawedBack(address _vestee, uint256 _amount) public {
        vm.expectEmit(true, false, false, true);
        emit ClawedBack(_vestee, _amount);
    }
}

// Deployment sanity checks.
contract NVTDeployment is NVTTest {

    function test_Deployment() public {
        assertEq(nvt.name(), "NDAO Voting Token");
        assertEq(nvt.symbol(), "NVT");
        assertEq(nvt.decimals(), 18);
        assertEq(address(nvt.ndao()), address(ndao));
    }
}

// Testing that NVT tokens can be delegated
contract Delegatable is NVTTest {
    function testFuzz_DelegateToAnotherAccount(
        address _holder,
        address _delegatee,
        uint256 _holdAmount
    ) public {
        vm.assume(
            _holder != address(0) &&
            _delegatee != address(0) &&
            _holder != _delegatee
        );
        _holdAmount = bound(_holdAmount, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _holdAmount);

        vm.prank(_holder);
        nvt.delegate(_delegatee);
        assertEq(nvt.getVotes(_delegatee), _holdAmount);
        assertEq(nvt.getVotes(_holder), 0);
    }

    function testFuzz_DelegateToSelf(
        address _holder,
        uint256 _holdAmount
    ) public {
        vm.assume(_holder != address(0));
        _holdAmount = bound(_holdAmount, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _holdAmount);

        vm.prank(_holder);
        nvt.delegate(_holder);
        assertEq(nvt.getVotes(_holder), _holdAmount);
    }

    function testFuzz_DelegateAndChange(
        address _holder,
        address _delegatee,
        address _secondDelegatee,
        uint256 _holdAmount
    ) public {
        vm.assume(
            _holder != address(0) &&
            _delegatee != address(0) &&
            _secondDelegatee != address(0) &&
            _delegatee != _secondDelegatee &&
            _holder != _delegatee &&
            _holder != _secondDelegatee
        );
        _holdAmount = bound(_holdAmount, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _holdAmount);

        vm.startPrank(_holder);
        nvt.delegate(_delegatee);
        assertEq(nvt.getVotes(_delegatee), _holdAmount);
        nvt.delegate(_secondDelegatee);
        assertEq(nvt.getVotes(_delegatee), 0);
        assertEq(nvt.getVotes(_secondDelegatee), _holdAmount);
        vm.stopPrank();
    }

    function testFuzz_DelegateRemovedAfterVotesUnlocked(address _holder, uint256 _amount, address _delegatee) public {
        vm.assume(
            _holder != address(0) &&
            _delegatee != address(0) &&
            _holder != _delegatee
        );
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        vm.prank(_holder);
        nvt.delegate(_delegatee);
        assertEq(nvt.getVotes(_delegatee), _amount);

        // None is available immediately
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);

        skip(365 days);

        // Unlock the full balance.
        UnlockRequest[] memory requests = new UnlockRequest[](1);
        requests[0] = UnlockRequest({
            index: 0,
            amount: _amount
        });
        vm.prank(_holder);
        nvt.unlock(requests);

        // Votes are delegated after unlock
        assertEq(nvt.getVotes(_delegatee), 0);
    }

    function testFuzz_DelegateIncreasedWhenMoreVotesLocked(
        address _holder,
        address _delegatee,
        uint256 _holdAmount
    ) public {
        vm.assume(
            _holder != address(0) &&
            _delegatee != address(0) &&
            _holder != _delegatee
        );
        _holdAmount = bound(_holdAmount, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _holdAmount);

        vm.prank(_holder);
        nvt.delegate(_delegatee);
        assertEq(nvt.getVotes(_delegatee), _holdAmount);

        mintNdaoAndVoteLock(_holder, _holdAmount);
        assertEq(nvt.getVotes(_delegatee), _holdAmount * 2);
    }

    function testFuzz_DelegateReflectPastState(
        address _holder,
        address _delegatee,
        uint256 _holdAmount
    ) public {
        vm.assume(
            _holder != address(0) &&
            _delegatee != address(0) &&
            _holder != _delegatee
        );
        _holdAmount = bound(_holdAmount, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _holdAmount);

        vm.prank(_holder);
        nvt.delegate(_delegatee);
        assertEq(nvt.getVotes(_delegatee), _holdAmount);
        assertEq(nvt.getVotes(_holder), 0);

        uint blockOfDelegation = block.number;

        vm.roll(100);

        mintNdaoAndVoteLock(_holder, _holdAmount);

        vm.prank(_holder);
        nvt.delegate(_delegatee);
        assertEq(nvt.getVotes(_delegatee), _holdAmount * 2);
        assertEq(nvt.getVotes(_holder), 0);

        assertEq(nvt.getPastVotes(_holder, blockOfDelegation), 0);
        assertEq(nvt.getPastVotes(_delegatee, blockOfDelegation), _holdAmount);
    }
}

// Testing that NVT tokens cannot be transferred.
contract NonTransferable is NVTTest {

    function testFuzz_CannotTransfer(
        address _holder,
        address _receiver,
        uint256 _holdAmount,
        uint256 _transferAmount
    ) public {
        vm.assume(
            _holder != address(0) &&
            _receiver != address(0)
        );
        _holdAmount = bound(_holdAmount, 0, MAX_DEPOSIT_AMOUNT);
        _transferAmount = bound(_transferAmount, 0, _holdAmount);

        mintNdaoAndVoteLock(_holder, _holdAmount);

        vm.expectRevert(TransferDisallowed.selector);
        vm.prank(_holder);
        nvt.transfer(_receiver, _transferAmount);
    }

    function testFuzz_CannotApprove(address _holder, address _spender, uint256 _approveAmount) public {
        vm.assume(
            _holder != address(0) &&
            _spender != address(0)
        );

        vm.expectRevert(TransferDisallowed.selector);
        vm.prank(_holder);
        nvt.approve(_spender, _approveAmount);
    }

    function testFuzz_CannotIncreaseAllowance(address _holder, address _spender, uint256 _increaseAmount) public {
        vm.assume(
            _holder != address(0) &&
            _spender != address(0)
        );

        vm.expectRevert(TransferDisallowed.selector);
        vm.prank(_holder);
        nvt.increaseAllowance(_spender, _increaseAmount);
    }

    function testFuzz_CannotDecreaseAllowance(address _holder, address _spender, uint256 _decreaseAmount) public {
        vm.assume(
            _holder != address(0) &&
            _spender != address(0)
        );

        vm.expectRevert(TransferDisallowed.selector);
        vm.prank(_holder);
        nvt.increaseAllowance(_spender, _decreaseAmount);
    }

    function testFuzz_CannotTransferFrom(
        address _holder,
        address _spender,
        address _receiver,
        uint256 _holdAmount,
        uint256 _transferAmount
    ) public {
        vm.assume(
            _holder != address(0) &&
            _receiver != address(0) &&
            _spender != address(0)
        );
        _holdAmount = bound(_holdAmount, 0, MAX_DEPOSIT_AMOUNT);
        _transferAmount = bound(_transferAmount, 0, _holdAmount);

        mintNdaoAndVoteLock(_holder, _holdAmount);

        vm.expectRevert(TransferDisallowed.selector);
        vm.prank(_spender);
        nvt.transferFrom(_holder, _receiver, _transferAmount);
    }
}

// Testing the ability to lock NDAO for NVT.
contract VoteLock is NVTTest {

    function testFuzz_NdaoHolderCanVoteLockNvt(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndApproveNvt(_holder, _amount);

        vm.prank(_holder);
        nvt.voteLock(_amount);

        assertEq(ndao.balanceOf(_holder), 0);
        assertEq(nvt.balanceOf(_holder), _amount);
    }

    function testFuzz_EventEmittedOnVoteLock(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndApproveNvt(_holder, _amount);

        vm.prank(_holder);
        expectEvent_Locked(_holder, 0, _amount);
        nvt.voteLock(_amount);
    }

    function testFuzz_NdaoHolderCanVoteLockNvtMultipleTimes(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndApproveNvt(_holder, _amount1);
        vm.prank(_holder);
        nvt.voteLock(_amount1);

        assertEq(ndao.balanceOf(_holder), 0);
        assertEq(nvt.balanceOf(_holder), _amount1);

        mintNdaoAndApproveNvt(_holder, _amount2);
        vm.prank(_holder);
        nvt.voteLock(_amount2);

        assertEq(ndao.balanceOf(_holder), 0);
        assertEq(nvt.balanceOf(_holder), _amount1 + _amount2);
    }

    function testFuzz_EventEmittedOnMultipleVoteLocks(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndApproveNvt(_holder, _amount1);
        mintNdaoAndApproveNvt(_holder, _amount2);

        vm.prank(_holder);
        expectEvent_Locked(_holder, 0, _amount1);
        nvt.voteLock(_amount1);

        vm.prank(_holder);
        expectEvent_Locked(_holder, 1, _amount2);
        nvt.voteLock(_amount2);
    }

    function testFuzz_CannotVoteLockWithoutNdao(address _holder, uint256 _amount) public {
        vm.assume(_holder != address(0));
        _amount = bound(_amount, 1, MAX_DEPOSIT_AMOUNT);

        vm.prank(_holder);
        ndao.approve(address(nvt), type(uint256).max);

        vm.expectRevert(ErrorNoNdaoTokensError);
        vm.prank(_holder);
        nvt.voteLock(_amount);
    }
}

// Testing deposits are recorded when tokens are locked.
contract Deposits is NVTTest {

    function testFuzz_RecordsDepositOnVoteLock(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        assertEq(nvt.getNumDeposits(_holder), 0);

        mintNdaoAndVoteLock(_holder, _amount);
        Deposit memory deposit = nvt.getDeposit(_holder, 0);

        assertEq(deposit.date, block.timestamp);
        assertEq(deposit.amount, _amount);
        assertEq(deposit.balance, _amount);
        assertEq(nvt.getNumDeposits(_holder), 1);
    }

    function testFuzz_MultipleDeposits(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _amount1);
        mintNdaoAndVoteLock(_holder, _amount2);

        Deposit memory deposit1 = nvt.getDeposit(_holder, 0);
        Deposit memory deposit2 = nvt.getDeposit(_holder, 1);

        assertEq(deposit1.date, block.timestamp);
        assertEq(deposit1.amount, _amount1);
        assertEq(deposit1.balance, _amount1);

        assertEq(deposit2.date, block.timestamp);
        assertEq(deposit2.amount, _amount2);
        assertEq(deposit2.balance, _amount2);
    }

    function testFuzz_MultipleDepositsOverTimeSpan(address _holder, uint256 _amount1, uint256 _amount2, uint256 _time) public {
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);
        _time = bound(_time, 0, 1000 * (365 days));

        mintNdaoAndVoteLock(_holder, _amount1);

        uint256 originalTimestamp = block.timestamp;
        skip(_time);

        mintNdaoAndVoteLock(_holder, _amount2);

        Deposit memory deposit1 = nvt.getDeposit(_holder, 0);
        Deposit memory deposit2 = nvt.getDeposit(_holder, 1);

        assertEq(deposit1.date, originalTimestamp);
        assertEq(deposit1.amount, _amount1);
        assertEq(deposit1.balance, _amount1);

        assertEq(deposit2.date, block.timestamp);
        assertEq(deposit2.amount, _amount2);
        assertEq(deposit2.balance, _amount2);
    }

    function testFuzz_DepositsFromMultipleHolders(
        address _holder1,
        address _holder2,
        uint256 _amount1,
        uint256 _amount2
    ) public {
        vm.assume(_holder1 != _holder2);
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder1, _amount1);
        mintNdaoAndVoteLock(_holder2, _amount2);

        Deposit memory deposit1 = nvt.getDeposit(_holder1, 0);
        Deposit memory deposit2 = nvt.getDeposit(_holder2, 0);

        assertEq(deposit1.date, block.timestamp);
        assertEq(deposit1.amount, _amount1);
        assertEq(deposit1.balance, _amount1);

        assertEq(deposit2.date, block.timestamp);
        assertEq(deposit2.amount, _amount2);
        assertEq(deposit2.balance, _amount2);
    }

    function testFuzz_DepositThatIsPartiallyUnlocked(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        // move one third of a year into the future
        uint256 originalTimestamp = block.timestamp;
        skip((365 days) / 3);

        // Unlock one third of the balance
        UnlockRequest[] memory requests = new UnlockRequest[](1);
        requests[0] = UnlockRequest({
            index: 0,
            amount: _amount / 3
        });
        vm.prank(_holder);
        nvt.unlock(requests);

        Deposit memory deposit = nvt.getDeposit(_holder, 0);

        assertEq(deposit.date, originalTimestamp);
        assertEq(deposit.amount, _amount);
        assertEq(deposit.balance, _amount - _amount / 3);
    }

    function testFuzz_DepositThatIsFullyUnlocked(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        // Move one year into the future.
        uint256 originalTimestamp = block.timestamp;
        skip(365 days);

        // Unlock the full balance.
        UnlockRequest[] memory requests = new UnlockRequest[](1);
        requests[0] = UnlockRequest({
            index: 0,
            amount: _amount
        });
        vm.prank(_holder);
        nvt.unlock(requests);

        Deposit memory deposit = nvt.getDeposit(_holder, 0);

        assertEq(deposit.date, originalTimestamp);
        assertEq(deposit.amount, _amount);
    }
}

// Testing the view helper which determines how many tokens are eligible to unlock.
contract WithdrawalAvailable is NVTTest {

    function testFuzz_ZeroAvailableImmediately(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);
    }

    function testFuzz_OneQuarterAvailableAfterQuarter(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);

        skip((365 days) / 4);

        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), _amount / 4);
    }

    function testFuzz_OneThirdAvailableAfterThirdOfYear(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);

        skip((365 days) / 3);

        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), _amount / 3);
    }

    function testFuzz_FiveSixthsAvailableAfterFiveSixthsOfYear(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);

        skip((5 * (365 days)) / 6);

        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), (5 * _amount) / 6);
    }

    function testFuzz_TwoSimultaneousDeposits(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _amount1);
        mintNdaoAndVoteLock(_holder, _amount2);

        // None is available immediately
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);
        assertEq(nvt.availableForWithdrawal(_holder, 1, block.timestamp), 0);

        uint256 timestamp = block.timestamp + (365 days) / 5;

        // 1/5th is available after 1/5th of a year
        assertEq(nvt.availableForWithdrawal(_holder, 0, timestamp), _amount1 / 5);
        assertEq(nvt.availableForWithdrawal(_holder, 1, timestamp), _amount2 / 5);

        timestamp = block.timestamp + (365 days);

        // All is available after a full year
        assertEq(nvt.availableForWithdrawal(_holder, 0, timestamp), _amount1);
        assertEq(nvt.availableForWithdrawal(_holder, 1, timestamp), _amount2);
    }

    function testFuzz_TwoDepositsOverTimeSpan(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        // mint, jump ahead a quarter, mint more
        mintNdaoAndVoteLock(_holder, _amount1);
        skip((365 days) / 4);
        mintNdaoAndVoteLock(_holder, _amount2);

        // What's available immediately
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), _amount1 / 4);
        assertEq(nvt.availableForWithdrawal(_holder, 1, block.timestamp), 0);

        // What's available after another 3/4s (a full year from initial deposit)
        uint256 timestamp = block.timestamp + (3 * (365 days)) / 4;
        assertEq(nvt.availableForWithdrawal(_holder, 0, timestamp), _amount1);
        assertEq(nvt.availableForWithdrawal(_holder, 1, timestamp), (3 * _amount2) / 4);
    }

    function testFuzz_DepositsFromMultipleHolders(
        address _holder1,
        address _holder2,
        uint256 _amount1,
        uint256 _amount2
    ) public {
        vm.assume(_holder1 != _holder2);
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder1, _amount1);
        mintNdaoAndVoteLock(_holder2, _amount2);

        // None is available immediately
        assertEq(nvt.availableForWithdrawal(_holder1, 0, block.timestamp), 0);
        assertEq(nvt.availableForWithdrawal(_holder2, 0, block.timestamp), 0);

        uint256 timestamp = block.timestamp + (365 days) / 6;

        // 1/6th is available after 1/6th of a year
        assertEq(nvt.availableForWithdrawal(_holder1, 0, timestamp), _amount1 / 6);
        assertEq(nvt.availableForWithdrawal(_holder2, 0, timestamp), _amount2 / 6);

        timestamp = block.timestamp + (365 days);

        // All is available after a full year
        assertEq(nvt.availableForWithdrawal(_holder1, 0, timestamp), _amount1);
        assertEq(nvt.availableForWithdrawal(_holder2, 0, timestamp), _amount2);
    }

    function testFuzz_AfterOneDepositThatHasBeenUnlocked(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        // None is available immediately
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);

        skip((365 days) / 4);

        // A quarter is available after a quarter, before unlock
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), _amount / 4);

        // Unlock everything that's available
        UnlockRequest[] memory requests = new UnlockRequest[](1);
        requests[0] = UnlockRequest({
            index: 0,
            amount: _amount / 4
        });
        vm.prank(_holder);
        nvt.unlock(requests);

        // Now none is available after unlock
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);

        // A year later, the balance is available for withdraw
        uint256 timestamp = block.timestamp + (365 days);
        assertEq(nvt.availableForWithdrawal(_holder, 0, timestamp), _amount - _amount / 4);
    }

    function testFuzz_OneDepositAfterArbitraryTime(address _holder, uint256 _amount, uint256 _time) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        _time = bound(_time, 0, 365 days);

        mintNdaoAndVoteLock(_holder, _amount);
        uint256 timestamp = block.timestamp + _time;
        uint256 expectedAmount = (_time * _amount) / (365 days);

        assertEq(nvt.availableForWithdrawal(_holder, 0, timestamp), expectedAmount);
    }

    function testFuzz_OneDepositAfterArbitraryTimeOver1Year(address _holder, uint256 _amount, uint256 _time) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        _time = bound(_time, 365 days, 1000 * (365 days));

        mintNdaoAndVoteLock(_holder, _amount);
        uint256 timestamp = block.timestamp + _time;

        assertEq(nvt.availableForWithdrawal(_holder, 0, timestamp), _amount);
    }
}

// Testing the ability to unlock NDAO with NVT.
contract Unlock is NVTTest {
    UnlockRequest[] testRequests;

    function testFuzz_UnlockAllAfterYear(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        skip(365 days);

        testRequests.push(UnlockRequest({
            index: 0,
            amount: _amount
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        assertEq(ndao.balanceOf(_holder), _amount);
        assertEq(nvt.balanceOf(_holder), 0);
    }

    function testFuzz_UnlockEmitsEvent(address _holder, uint256 _lockAmount, uint256 _unlockAmount) public {
        _lockAmount = bound(_lockAmount, 0, MAX_DEPOSIT_AMOUNT);
        _unlockAmount = bound(_unlockAmount, 0, _lockAmount);
        mintNdaoAndVoteLock(_holder, _lockAmount);

        skip(365 days);

        testRequests.push(UnlockRequest({
            index: 0,
            amount: _unlockAmount
        }));

        vm.prank(_holder);
        expectEvent_Unlocked(_holder, 0, _unlockAmount);
        nvt.unlock(testRequests);
    }

    function testFuzz_UnlockOneQuarterAfterQuarter(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        skip((365 days) / 4);

        testRequests.push(UnlockRequest({
            index: 0,
            amount: (_amount / 4)
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        assertEq(ndao.balanceOf(_holder), _amount / 4);
        assertEq(nvt.balanceOf(_holder), _amount - (_amount / 4));
    }

    function testFuzz_UnlockOneEighthAfterQuarter(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        skip((365 days) / 4);

        testRequests.push(UnlockRequest({
            index: 0,
            amount: (_amount / 8)
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        assertEq(ndao.balanceOf(_holder), _amount / 8);
        assertEq(nvt.balanceOf(_holder), _amount - (_amount / 8));
    }

    function testFuzz_UnlockQuarterInTwoRequests(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        skip((365 days) / 4);

        // Request less than what's available
        testRequests.push(
            UnlockRequest({
                index: 0,
                amount: (_amount / 6)
            })
        );

        // Request what's left after the prior request
        testRequests.push(UnlockRequest({
            index: 0,
            amount: ( (_amount / 4) - (_amount / 6) )
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        assertEq(ndao.balanceOf(_holder), _amount / 4);
        assertEq(nvt.balanceOf(_holder), _amount - (_amount / 4));
    }

    function testFuzz_UnlockOverTwoTimeSpans(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        skip((365 days) / 4);

        testRequests.push(UnlockRequest({
            index: 0,
            amount: (_amount / 4)
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        delete testRequests;
        skip((365 days) / 6);

        testRequests.push(UnlockRequest({
            index: 0,
            amount: (_amount / 6)
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        assertEq(ndao.balanceOf(_holder), (_amount / 4) + (_amount / 6));
        assertEq(nvt.balanceOf(_holder), _amount - (_amount / 4) - (_amount / 6));
    }

    function testFuzz_UnlockTwoDeposits(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _amount1);
        skip((365 days) / 4);
        mintNdaoAndVoteLock(_holder, _amount2);
        skip((365 days) / 6);

        uint256 _amount1Unlocked = (10 * _amount1) / 24; // (1/4) + (1/6) = (10/24)
        uint256 _amount2Unlocked = _amount2 / 6;

        testRequests.push(UnlockRequest({
            index: 0,
            amount: _amount1Unlocked
        }));

        testRequests.push(UnlockRequest({
            index: 1,
            amount: _amount2Unlocked
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        assertEq(ndao.balanceOf(_holder), _amount1Unlocked + _amount2Unlocked);
        assertEq(nvt.balanceOf(_holder), _amount1 + _amount2 - _amount1Unlocked - _amount2Unlocked);
    }

    function testFuzz_UnlockingMultipleDepositsEmitsMultipleEvents(
        address _holder,
        uint256 _lockAmount1,
        uint256 _unlockAmount1,
        uint256 _lockAmount2,
        uint256 _unlockAmount2
    ) public {
        _lockAmount1 = bound(_lockAmount1, 0, MAX_DEPOSIT_AMOUNT);
        _unlockAmount1 = bound(_unlockAmount1, 0, _lockAmount1);
        mintNdaoAndVoteLock(_holder, _lockAmount1);

        _lockAmount2 = bound(_lockAmount2, 0, MAX_DEPOSIT_AMOUNT);
        _unlockAmount2 = bound(_unlockAmount2, 0, _lockAmount2);
        mintNdaoAndVoteLock(_holder, _lockAmount2);

        skip(365 days);

        testRequests.push(UnlockRequest({
            index: 0,
            amount: _unlockAmount1
        }));

        testRequests.push(UnlockRequest({
            index: 1,
            amount: _unlockAmount2
        }));

        vm.prank(_holder);
        expectEvent_Unlocked(_holder, 0, _unlockAmount1);
        expectEvent_Unlocked(_holder, 1, _unlockAmount2);
        nvt.unlock(testRequests);
    }

    function testFuzz_UnlockTwoDepositsOverTwoTimeSpans(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        // make a deposit and go ahead a quarter
        mintNdaoAndVoteLock(_holder, _amount1);
        skip((365 days) / 4);

        uint256 _amount1FirstUnlock = _amount1 / 8;

        // unlock some of the first deposit
        testRequests.push(UnlockRequest({
            index: 0,
            amount: _amount1FirstUnlock
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        assertEq(ndao.balanceOf(_holder), _amount1FirstUnlock);
        assertEq(nvt.balanceOf(_holder), _amount1 - _amount1FirstUnlock);

        delete testRequests;

        // make another deposit and go ahead a sixth of a year
        mintNdaoAndVoteLock(_holder, _amount2);
        skip((365 days) / 6);

        uint256 _amount1SecondUnlock = ((10 * _amount1) / 24) - (_amount1 / 8);
        uint256 _amount2Unlock = _amount2 / 8;

        // unlock all available from deposit 1
        testRequests.push(UnlockRequest({
            index: 0,
            amount: _amount1SecondUnlock
        }));

        // unlock some of what's available from deposit 2
        testRequests.push(UnlockRequest({
            index: 1,
            amount: _amount2Unlock
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        assertEq(ndao.balanceOf(_holder), _amount1FirstUnlock + _amount1SecondUnlock + _amount2Unlock);
        assertEq(nvt.balanceOf(_holder), _amount1 + _amount2 - _amount1FirstUnlock - _amount1SecondUnlock - _amount2Unlock);
    }

    function testFuzz_CannotUnlockMoreThanAvailable(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        skip((365 days) / 4);

        testRequests.push(
            UnlockRequest({
                index: 0,
                amount: ((_amount / 4) + 1)
            })
        );

        vm.prank(_holder);
        vm.expectRevert(InvalidUnlockRequest.selector);
        nvt.unlock(testRequests);
    }

    function testFuzz_CannotUnlockMoreThanAvailableInMultipleRequests(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        skip((365 days) / 4);

        // Request less than the quarter available
        testRequests.push(
            UnlockRequest({
                index: 0,
                amount: (_amount / 6)
            })
        );

        // Request one *more* than what's left after the prior request
        testRequests.push(
            UnlockRequest({
                index: 0,
                amount: ( (_amount / 4) - (_amount / 6) + 1 )
            })
        );

        vm.prank(_holder);
        vm.expectRevert(InvalidUnlockRequest.selector);
        nvt.unlock(testRequests);
    }

    function testFuzz_CannotUnlockMoreThanTwoDepositsOverTwoTimeSpans(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_DEPOSIT_AMOUNT);

        // make a deposit and go ahead a quarter
        mintNdaoAndVoteLock(_holder, _amount1);
        skip((365 days) / 4);

        uint256 _amount1FirstUnlock = _amount1 / 8;

        // unlock some of the first deposit
        testRequests.push(UnlockRequest({
            index: 0,
            amount: _amount1FirstUnlock
        }));

        vm.prank(_holder);
        nvt.unlock(testRequests);

        assertEq(ndao.balanceOf(_holder), _amount1FirstUnlock);
        assertEq(nvt.balanceOf(_holder), _amount1 - _amount1FirstUnlock);

        delete testRequests;

        // make another deposit and go ahead a sixth of a year
        mintNdaoAndVoteLock(_holder, _amount2);
        skip((365 days) / 6);

        uint256 _amount1SecondUnlock = ((10 * _amount1) / 24) - (_amount1 / 8) + 1;
        uint256 _amount2Unlock = _amount2 / 8;

        // unlock *more* than all available from deposit 1
        testRequests.push(UnlockRequest({
            index: 0,
            amount: _amount1SecondUnlock
        }));

        // unlock some of what's available from deposit 2
        testRequests.push(UnlockRequest({
            index: 1,
            amount: _amount2Unlock
        }));

        vm.prank(_holder);
        vm.expectRevert(InvalidUnlockRequest.selector);
        nvt.unlock(testRequests);
    }
}

// Testing the view, off-chain only integration helpers that return active deposits & total available for withdrawal.
contract OffChainHelpers is NVTTest {

    function testFuzz_NoDeposits(address _holder) public {
        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, block.timestamp);

        assertEq(activeIndices.length, 0);
        assertEq(_amountAvailable, 0);
    }

    function testFuzz_ImmediatelyAfterOneDeposit(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 1, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, block.timestamp);

        assertEq(activeIndices.length, 1);
        assertEq(activeIndices[0], 0);
        assertEq(_amountAvailable, 0);
    }

    function testFuzz_AfterOneDepositTimeElapsed(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 1, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        uint256 timestamp = block.timestamp + (365 days) / 4;
        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, timestamp);

        assertEq(activeIndices.length, 1);
        assertEq(activeIndices[0], 0);
        assertEq(_amountAvailable, _amount / 4);
    }

    function testFuzz_ImmediatelyAfterTwoDeposits(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 1, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 1, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _amount1);
        mintNdaoAndVoteLock(_holder, _amount2);

        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, block.timestamp);

        assertEq(activeIndices.length, 2);
        assertEq(activeIndices[0], 0);
        assertEq(activeIndices[1], 1);
        assertEq(_amountAvailable, 0);
    }

    function testFuzz_AfterTwoSimultaneousDepositsTimeElapsed(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 1, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 1, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _amount1);
        mintNdaoAndVoteLock(_holder, _amount2);

        uint256 timestamp = block.timestamp + (365 days) / 6;
        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, timestamp);

        assertEq(activeIndices.length, 2);
        assertEq(activeIndices[0], 0);
        assertEq(activeIndices[1], 1);
        assertEq(_amountAvailable, (_amount1 / 6) + (_amount2 / 6));
    }

    function testFuzz_AfterTwoDepositsAcrossTimeSpans(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 1, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 1, MAX_DEPOSIT_AMOUNT);

        // vote lock some ndao
        mintNdaoAndVoteLock(_holder, _amount1);
        // jump ahead a third of a year
        skip((365 days) / 3);
        // vote lock some more ndao
        mintNdaoAndVoteLock(_holder, _amount2);

        // we'll look another fifth of a year in the future, 8 / 15ths of a year total
        uint256 timestamp = block.timestamp + (365 days) / 5;
        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, timestamp);

        assertEq(activeIndices.length, 2);
        assertEq(activeIndices[0], 0);
        assertEq(activeIndices[1], 1);
        assertEq(_amountAvailable, ((8 * _amount1) / 15) + (_amount2 / 5));
    }

    function testFuzz_AfterOneDepositThatHasBeenUnlocked(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, MAX_DEPOSIT_AMOUNT);
        mintNdaoAndVoteLock(_holder, _amount);

        skip(365 days);

        UnlockRequest[] memory requests = new UnlockRequest[](1);
        requests[0] = UnlockRequest({
            index: 0,
            amount: _amount
        });
        vm.prank(_holder);
        nvt.unlock(requests);

        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, block.timestamp);

        assertEq(activeIndices.length, 0);
        assertEq(_amountAvailable, 0);
    }

    function testFuzz_AfterTwoSimultaneousDepositsWhenOneHasBeenUnlocked(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 1, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 1, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _amount1);
        mintNdaoAndVoteLock(_holder, _amount2);

        skip(365 days);

        UnlockRequest[] memory requests = new UnlockRequest[](1);
        requests[0] = UnlockRequest({
            index: 0,
            amount: _amount1
        });
        vm.prank(_holder);
        nvt.unlock(requests);

        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, block.timestamp);

        assertEq(activeIndices.length, 1);
        assertEq(activeIndices[0], 1);
        assertEq(_amountAvailable, _amount2);
    }

    function testFuzz_AfterTwoSimultaneousDepositsWhenOneHasBeenPartiallyUnlocked(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 1, MAX_DEPOSIT_AMOUNT);
        _amount2 = bound(_amount2, 1, MAX_DEPOSIT_AMOUNT);

        mintNdaoAndVoteLock(_holder, _amount1);
        mintNdaoAndVoteLock(_holder, _amount2);

        skip(365 days);

        // unlock a third of the second deposit only
        UnlockRequest[] memory requests = new UnlockRequest[](1);
        requests[0] = UnlockRequest({
            index: 1,
            amount: (_amount2 / 3)
        });
        vm.prank(_holder);
        nvt.unlock(requests);

        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, block.timestamp);

        assertEq(activeIndices.length, 2);
        assertEq(activeIndices[0], 0);
        assertEq(activeIndices[1], 1);
        assertEq(_amountAvailable, _amount1 + _amount2 - (_amount2 / 3));
    }
}

// Testing when authorized user can or cannot lock NDAO and create vesting NVT distributions.
contract VestLock is NVTTest {

    function testFuzz_AuthorizedUserCanVestLock(
        address _vestee,
        uint256 _amount,
        uint256 _period,
        uint256 _seed
    ) public {
        address _actor = getAuthorizedActor(_seed);
        vm.assume(
            _vestee != _actor &&
            _vestee != address(0)
        );
        _amount = bound(_amount, 0, MAX_VESTING_AMOUNT);
        _period = bound(_period, 1, MAX_VESTING_PERIOD);
        mintNdaoAndApproveNvt(_actor, _amount);

        vm.prank(_actor);
        expectEvent_VestLocked(_vestee, _amount, _period);
        nvt.vestLock(_vestee, _amount, _period);

        VestingSchedule memory _schedule = nvt.getVestingSchedule(_vestee);

        assertEq(ndao.balanceOf(address(nvt)), _amount);
        assertEq(nvt.balanceOf(_vestee), _amount);
        assertEq(_schedule.startDate, block.timestamp);
        assertEq(_schedule.vestDate, block.timestamp + _period);
    }

    function testFuzz_CannotVestLockForZeroSeconds(address _vestee, uint256 _amount) public {
        vm.expectRevert(InvalidVestingPeriod.selector);
        vm.prank(board);
        nvt.vestLock(_vestee, _amount, 0);
    }

    function testFuzz_CannotVestToSameAccountTwice(
        address _vestee,
        uint256 _amount1,
        uint256 _amount2,
        uint256 _period1,
        uint256 _period2
    ) public {
        vm.assume(
            _vestee != board &&
            _vestee != address(0)
        );
        _amount1 = bound(_amount1, 0, MAX_VESTING_AMOUNT);
        _amount2 = bound(_amount2, 0, MAX_VESTING_AMOUNT);
        _period1 = bound(_period1, 1, MAX_VESTING_PERIOD);
        _period2 = bound(_period2, 1, MAX_VESTING_PERIOD);

        mintNdaoAndApproveNvt(board, _amount1 + _amount2);

        vm.startPrank(board);
        nvt.vestLock(_vestee, _amount1, _period1);
        vm.expectRevert(AccountAlreadyVesting.selector);
        nvt.vestLock(_vestee, _amount2, _period2);
        vm.stopPrank();
    }

    function testFuzz_NonAuthorizedCannotVestLock(
        address _nonAdmin,
        address _vestee,
        uint256 _amount,
        uint256 _period
    ) public {
        vm.assume(
            _nonAdmin != board &&
            _nonAdmin != capitalCommittee
        );

        vm.expectRevert(Unauthorized.selector);
        vm.prank(_nonAdmin);
        nvt.vestLock(_vestee, _amount, _period);
    }
}

// Testing the view helper that calculates how much vested NVT is available to the vestee to be unlocked.
contract AvailableForVestUnlock is NVTTest {

    function testFuzz_AvailableForVestAfterArbitraryTime(
        address _vestee,
        uint256 _amount,
        uint256 _period,
        uint256 _time
    ) public {
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        _period = bound(_period, 1, MAX_VESTING_PERIOD);
        _time = bound(_time, 0, _period);

        mintNdaoAndVest(_vestee, _amount, _period);
        uint256 _timestamp = block.timestamp + _time;
        uint256 _expected = (_amount * _time) / _period;

        assertEq(nvt.availableForVestUnlock(_vestee, _timestamp), _expected);
    }

    function testFuzz_AvailableAfterVestedAndWithdrawingArbitraryAmount(
        address _vestee,
        uint256 _vestAmount,
        uint256 _withdrawAmount,
        uint256 _period
    ) public {
        _vestAmount = bound(_vestAmount, 1, MAX_VESTING_AMOUNT);
        _withdrawAmount = bound(_withdrawAmount, 0, _vestAmount);
        _period = bound(_period, 1, MAX_VESTING_PERIOD);

        // Vest then jump to fully vested date.
        mintNdaoAndVest(_vestee, _vestAmount, _period);
        skip(_period);

        // Withdraw some of the vest.
        vm.prank(_vestee);
        nvt.unlockVested(_withdrawAmount);

        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), _vestAmount - _withdrawAmount);
    }

    function testFuzz_AvailableAfterWithdrawingAllVested(address _vestee, uint256 _amount) public {
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        uint256 _period = 4 * (365 days);
        mintNdaoAndVest(_vestee, _amount, _period);

        // Jump ahead a quarter of the vesting period.
        skip(_period / 4);

        // Unlock a quarter of funds, i.e. all vested.
        vm.prank(_vestee);
        nvt.unlockVested(_amount / 4);

        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), 0);
    }

    function testFuzz_AvailableAfterPartialWithdrawalAndMultipleTimeSpans(
        address _vestee,
        uint256 _amount
    ) public {
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        uint256 _period = 4 * (365 days);
        mintNdaoAndVest(_vestee, _amount, _period);

        skip(_period / 3);

        // Unlock a quarter of funds, a subset of what is vested.
        vm.prank(_vestee);
        nvt.unlockVested(_amount / 4);
        uint256 _expected = _amount / 3 - _amount / 4;

        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), _expected);

        uint256 _timestamp = block.timestamp + _period;
        assertEq(nvt.availableForVestUnlock(_vestee, _timestamp), _amount - _amount / 4);
    }
}

// Testing the ability of the vestee to unlock vested NVT for NDAO.
contract UnlockVested is NVTTest {

    function testFuzz_VesteeCannotUnlockAnyImmediately(address _vestee, uint256 _vestAmount, uint256 _period) public {
        _vestAmount = bound(_vestAmount, 1, MAX_VESTING_AMOUNT);
        _period = bound(_period, 1, MAX_VESTING_PERIOD);
        mintNdaoAndVest(_vestee, _vestAmount, _period);

        vm.prank(_vestee);
        vm.expectRevert(InvalidUnlockRequest.selector);
        nvt.unlockVested(1);
    }

    function testFuzz_VesteeCanUnlockAllAtFullVest(address _vestee, uint256 _amount, uint256 _period) public {
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        _period = bound(_period, 1, MAX_VESTING_PERIOD);
        mintNdaoAndVest(_vestee, _amount, _period);

        skip(_period);

        vm.prank(_vestee);
        expectEvent_VestUnlocked(_vestee, _amount);
        nvt.unlockVested(_amount);

        assertEq(nvt.balanceOf(_vestee), 0);
        assertEq(ndao.balanceOf(_vestee), _amount);
        assertEq(ndao.balanceOf(address(nvt)), 0);
    }

    function testFuzz_VesteeUnlockQuarterAfterQuarter(address _vestee, uint256 _amount) public {
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        uint256 _period = 2 * (365 days);
        mintNdaoAndVest(_vestee, _amount, _period);

        // Jump ahead a quarter of the period.
        skip(_period / 4);

        // Unlock a quarter of the total, i.e. all that's vested.
        vm.prank(_vestee);
        nvt.unlockVested(_amount / 4);

        assertEq(nvt.balanceOf(_vestee), _amount - _amount / 4);
        assertEq(ndao.balanceOf(_vestee), _amount / 4);
    }

    function testFuzz_VesteeUnlockPartialAvailable(address _vestee, uint256 _amount) public {
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        uint256 _period = 2 * (365 days);
        mintNdaoAndVest(_vestee, _amount, _period);

        // Jump ahead half the period.
        skip(_period / 2);

        // Unlock a third of total, i.e. only a portion of what's vested.
        vm.prank(_vestee);
        expectEvent_VestUnlocked(_vestee, _amount / 3);
        nvt.unlockVested(_amount / 3);

        assertEq(nvt.balanceOf(_vestee), _amount - _amount / 3);
        assertEq(ndao.balanceOf(_vestee), _amount / 3);
    }

    function testFuzz_VesteeUnlockOverTwoTimeSpans(address _vestee, uint256 _amount) public {
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        uint256 _period = 2 * (365 days);
        mintNdaoAndVest(_vestee, _amount, _period);

        // Jump ahead a third of period.
        skip(_period / 3);

        // Unlock some of what's vested, a quarter.
        vm.prank(_vestee);
        nvt.unlockVested(_amount / 4);

        assertEq(nvt.balanceOf(_vestee), _amount - _amount / 4);
        assertEq(ndao.balanceOf(_vestee), _amount / 4);

        // Jump ahead another period, well past the vest date.
        skip(_period);

        // Unlock the rest of the staked NVT.
        vm.prank(_vestee);
        nvt.unlockVested(_amount - _amount / 4);

        assertEq(nvt.balanceOf(_vestee), 0);
        assertEq(ndao.balanceOf(_vestee), _amount);
    }

    function testFuzz_CannotUnlockVestedTokensTwice(address _vestee, address _holder, uint256 _amount) public {
        vm.assume(_vestee != _holder);
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT / 2);
        uint256 _period = 2 * (365 days);
        mintNdaoAndVest(_vestee, _amount, _period);
        // Mint and lock some other tokens that the vestee could 'steal.'
        mintNdaoAndVoteLock(_holder, _amount);

        // Jump ahead the period.
        skip(_period);

        // Unlock it all.
        vm.prank(_vestee);
        nvt.unlockVested(_amount);

        assertEq(nvt.balanceOf(_vestee), 0);
        assertEq(ndao.balanceOf(_vestee), _amount);

        // Try to unlock it again.
        vm.prank(_vestee);
        vm.expectRevert(InvalidUnlockRequest.selector);
        nvt.unlockVested(_amount);
    }
}

// Testing the ability of authorized accounts to clawback non-vested NVT from a vestee.
contract Clawback is NVTTest {

    function testFuzz_ClawbackAllImmediately(address _vestee, uint256 _amount, uint256 _period, uint256 _seed) public {
        address _actor = getAuthorizedActor(_seed);
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        _period = bound(_period, 1, MAX_VESTING_PERIOD);
        mintNdaoAndVest(_vestee, _amount, _period);

        vm.prank(_actor);
        expectEvent_ClawedBack(_vestee, _amount);
        nvt.clawback(_vestee);

        uint256 _vestDate = block.timestamp + _period;
        VestingSchedule memory _schedule = nvt.getVestingSchedule(_vestee);

        assertEq(ndao.balanceOf(_actor), _amount);
        assertEq(nvt.availableForVestUnlock(_vestee, _vestDate), 0);
        assertEq(_schedule.balance, 0);
        assertTrue(_schedule.wasClawedBack);
    }

    function testFuzz_NothingToClawbackOnSecondCall(
        address _vestee,
        address _holder,
        uint256 _amount,
        uint256 _period,
        uint256 _seed
    ) public {
        address _actor = getAuthorizedActor(_seed);
        vm.assume(_vestee != _holder);
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT / 2);
        _period = bound(_period, 1, MAX_VESTING_PERIOD);
        mintNdaoAndVest(_vestee, _amount, _period);
        // Mint and lock some other ndao the actor could 'steal.'
        mintNdaoAndVoteLock(_holder, _amount);

        // Clawback.
        vm.prank(_actor);
        expectEvent_ClawedBack(_vestee, _amount);
        nvt.clawback(_vestee);

        uint256 _vestDate = block.timestamp + _period;

        assertEq(ndao.balanceOf(_actor), _amount);
        assertEq(nvt.availableForVestUnlock(_vestee, _vestDate), 0);

        // Try to clawback again.
        vm.prank(_actor);
        expectEvent_ClawedBack(_vestee, 0);
        nvt.clawback(_vestee);

        // There is no change because there is nothing to clawback.
        assertEq(ndao.balanceOf(_actor), _amount);
        assertEq(ndao.balanceOf(address(nvt)), _amount);
        assertEq(nvt.availableForVestUnlock(_vestee, _vestDate), 0);
    }

    function testFuzz_CannotClawbackVestedTokens(address _vestee, uint256 _amount, uint256 _seed) public {
        address _actor = getAuthorizedActor(_seed);
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        uint256 _period = 547 days; // ~1.5 years
        mintNdaoAndVest(_vestee, _amount, _period);

        // Jump ahead a third of the vesting period.
        skip(_period / 3);

        uint256 _expectedVested = _amount / 3;
        uint256 _expectedClawback = _amount - _expectedVested;

        // Clawback unvested tokens, i.e 2/3rds
        vm.prank(_actor);
        expectEvent_ClawedBack(_vestee, _expectedClawback);
        nvt.clawback(_vestee);

        assertEq(ndao.balanceOf(_actor), _expectedClawback);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), _expectedVested);

        // Jump ahead another bit of time.
        skip(_period / 2);

        // The vestee should still have the original vested tokens available to claim.
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), _expectedVested);

        // The vestee should be able to unlock them.
        vm.prank(_vestee);
        nvt.unlockVested(_expectedVested);

        assertEq(ndao.balanceOf(_vestee), _expectedVested);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), 0);
    }

    function testFuzz_ClawbackAfterVestingAndPartialWithdraw(address _vestee, uint256 _amount, uint256 _seed) public {
        address _actor = getAuthorizedActor(_seed);
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        uint256 _period = 547 days; // ~1.5 years
        mintNdaoAndVest(_vestee, _amount, _period);

        // Jump ahead a third of the vesting period.
        skip(_period / 3);

        // Unlock a subset of what is vested.
        vm.prank(_vestee);
        nvt.unlockVested(_amount / 4);

        // Sanity check unlock.
        assertEq(ndao.balanceOf(_vestee), _amount / 4);

        // Clawback unvested tokens, i.e. 2/3rds.
        vm.prank(_actor);
        nvt.clawback(_vestee);

        uint256 _expectedVested = _amount / 3;
        uint256 _expectedClawback = _amount - _expectedVested;
        uint256 _expectedAvailable = _expectedVested - _amount / 4;

        assertEq(ndao.balanceOf(_actor), _expectedClawback);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), _expectedAvailable);
        // At various points in the future the amount available is still the same.
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period / 2), _expectedAvailable);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period), _expectedAvailable);

        // The vestee should be able to unlock remaining balance.
        vm.prank(_vestee);
        nvt.unlockVested(_expectedAvailable);

        assertEq(ndao.balanceOf(_vestee), _expectedVested);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), 0);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period / 2), 0);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period), 0);
    }

    function testFuzz_PartialWithdrawAfterClawback(address _vestee, uint256 _amount, uint256 _seed) public {
        address _actor = getAuthorizedActor(_seed);
        _amount = bound(_amount, 1, MAX_VESTING_AMOUNT);
        uint256 _period = 547 days; // ~1.5 years
        mintNdaoAndVest(_vestee, _amount, _period);

        // Jump ahead a third of the vesting period.
        skip(_period / 3);

        // Clawback unvested tokens, i.e. 2/3rds.
        vm.prank(_actor);
        nvt.clawback(_vestee);

        uint256 _expectedVested = _amount / 3;
        uint256 _expectedClawback = _amount - _expectedVested;

        assertEq(ndao.balanceOf(_actor), _expectedClawback);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), _expectedVested);
        // At various points in the future the amount available is still the same.
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period / 2), _expectedVested);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period), _expectedVested);

        // Unlock a subset of what is vested.
        vm.prank(_vestee);
        nvt.unlockVested(_amount / 4);

        uint256 _expectedAvailable = _expectedVested - _amount / 4;

        assertEq(ndao.balanceOf(_vestee), _amount / 4);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), _expectedAvailable);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period / 2), _expectedAvailable);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period), _expectedAvailable);

        // The vestee should be able to unlock remaining balance.
        vm.prank(_vestee);
        nvt.unlockVested(_expectedAvailable);

        assertEq(ndao.balanceOf(_vestee), _expectedVested);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp), 0);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period / 2), 0);
        assertEq(nvt.availableForVestUnlock(_vestee, block.timestamp + _period), 0);
    }

    function testFuzz_NonAdminCannotCallClawback(address _nonAdmin, address _vestee) public {
        vm.assume(
            _nonAdmin != board &&
            _nonAdmin != capitalCommittee
        );

        vm.prank(_nonAdmin);
        vm.expectRevert(Unauthorized.selector);
        nvt.clawback(_vestee);
    }
}
