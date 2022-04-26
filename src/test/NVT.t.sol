// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { NVT, NVTTypes, INDAO } from "../NVT.sol";
import { NDAO } from "../NDAO.sol";

contract NVTTest is NVTTypes, DSTestPlus {
    NVT nvt;

    NDAO ndao;
    address admin = address(0xAD);

    bytes ErrorInvalidUnlockRequest = abi.encodeWithSelector(InvalidUnlockRequest.selector);

    // In the Solmate ERC20 implementation, attempting to transfer tokens you don't have reverts w/ an overflow panic
    bytes ErrorNoNdaoTokensError = abi.encodeWithSignature("Panic(uint256)", 0x11);

    function setUp() public virtual {
        vm.label(admin, "admin");

        ndao = new NDAO(admin);
        nvt = new NVT(INDAO(address(ndao)));

        vm.label(address(ndao), "NDAO");
        vm.label(address(nvt), "NVT");
    }

    function mintNdaoAndApproveNvt(address _holder, uint256 _amount) public {
        vm.assume(
            _holder != address(0) &&
            _holder != address(ndao) &&
            _holder != address(nvt)
        );

        vm.prank(admin);
        ndao.mint(_holder, _amount);

        vm.prank(_holder);
        ndao.approve(address(nvt), type(uint256).max);
    }

    function mintNdaoAndVoteLock(address _holder, uint256 _amount) public {
        mintNdaoAndApproveNvt(_holder, _amount);
        vm.prank(_holder);
        nvt.voteLock(_amount);
    }

    function expectEvent_Locked(address _holder, uint256 _depositIndex, uint256 _amount) public {
        vm.expectEmit(true, true, false, true);
        emit Locked(_holder, _depositIndex, _amount);
    }

    function expectEvent_Unlocked(address _holder, uint256 _depositIndex, uint256 _amount) public {
        vm.expectEmit(true, true, false, true);
        emit Unlocked(_holder, _depositIndex, _amount);
    }
}

// Deployment sanity checks.
contract Deployment is NVTTest {

    function test_Deployment() public {
        assertEq(nvt.name(), "NDAO Voting Token");
        assertEq(nvt.symbol(), "NVT");
        assertEq(nvt.decimals(), 18);
        assertEq(address(nvt.ndao()), address(ndao));
    }
}

// Testing the ability to lock NDAO for NVT.
contract VoteLock is NVTTest {

    function testFuzz_NdaoHolderCanVoteLockNvt(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, type(uint224).max); // Enforced via ERC20Votes._maxSupply()
        mintNdaoAndApproveNvt(_holder, _amount);

        vm.prank(_holder);
        nvt.voteLock(_amount);

        assertEq(ndao.balanceOf(_holder), 0);
        assertEq(nvt.balanceOf(_holder), _amount);
    }

    function testFuzz_EventEmittedOnVoteLock(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, type(uint224).max);
        mintNdaoAndApproveNvt(_holder, _amount);

        vm.prank(_holder);
        expectEvent_Locked(_holder, 0, _amount);
        nvt.voteLock(_amount);
    }

    function testFuzz_NdaoHolderCanVoteLockNvtMultipleTimes(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _amount = bound(_amount, 1, type(uint224).max);

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
        _amount = bound(_amount, 0, type(uint224).max);
        assertEq(nvt.getNumDeposits(_holder), 0);

        mintNdaoAndVoteLock(_holder, _amount);
        Deposit memory deposit = nvt.getDeposit(_holder, 0);

        assertEq(deposit.date, block.timestamp);
        assertEq(deposit.amount, _amount);
        assertEq(deposit.balance, _amount);
        assertEq(nvt.getNumDeposits(_holder), 1);
    }

    function testFuzz_MultipleDeposits(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _amount = bound(_amount, 0, type(uint224).max);
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
        _amount = bound(_amount, 0, type(uint224).max);
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
        _amount = bound(_amount, 0, type(uint224).max);
        mintNdaoAndVoteLock(_holder, _amount);

        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);
    }

    function testFuzz_OneQuarterAvailableAfterQuarter(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, type(uint224).max);
        mintNdaoAndVoteLock(_holder, _amount);
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);

        skip((365 days) / 4);

        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), _amount / 4);
    }

    function testFuzz_OneThirdAvailableAfterThirdOfYear(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, type(uint224).max);
        mintNdaoAndVoteLock(_holder, _amount);
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);

        skip((365 days) / 3);

        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), _amount / 3);
    }

    function testFuzz_FiveSixthsAvailableAfterFiveSixthsOfYear(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, type(uint224).max);
        mintNdaoAndVoteLock(_holder, _amount);
        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), 0);

        skip((5 * (365 days)) / 6);

        assertEq(nvt.availableForWithdrawal(_holder, 0, block.timestamp), (5 * _amount) / 6);
    }

    function testFuzz_TwoSimultaneousDeposits(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _amount = bound(_amount, 0, type(uint224).max);
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
        _amount = bound(_amount, 0, type(uint224).max);
        _time = bound(_time, 0, 365 days);

        mintNdaoAndVoteLock(_holder, _amount);
        uint256 timestamp = block.timestamp + _time;
        uint256 expectedAmount = (_time * _amount) / (365 days);

        assertEq(nvt.availableForWithdrawal(_holder, 0, timestamp), expectedAmount);
    }

    function testFuzz_OneDepositAfterArbitraryTimeOver1Year(address _holder, uint256 _amount, uint256 _time) public {
        _amount = bound(_amount, 0, type(uint224).max);
        _time = bound(_time, 365 days, type(uint256).max);

        mintNdaoAndVoteLock(_holder, _amount);
        uint256 timestamp = block.timestamp + _time;

        assertEq(nvt.availableForWithdrawal(_holder, 0, timestamp), _amount);
    }
}

// Testing the ability to unlock NDAO with NVT.
contract Unlock is NVTTest {
    UnlockRequest[] testRequests;

    function testFuzz_UnlockAllAfterYear(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, type(uint224).max);
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
        _lockAmount = bound(_lockAmount, 0, type(uint224).max);
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
        _amount = bound(_amount, 0, type(uint224).max);
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
        _amount = bound(_amount, 0, type(uint224).max);
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
        _amount = bound(_amount, 0, type(uint224).max);
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
        _amount = bound(_amount, 0, type(uint224).max);
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
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _lockAmount1 = bound(_lockAmount1, 0, type(uint112).max);
        _unlockAmount1 = bound(_unlockAmount1, 0, _lockAmount1);
        mintNdaoAndVoteLock(_holder, _lockAmount1);

        _lockAmount2 = bound(_lockAmount2, 0, type(uint112).max);
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
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        _amount = bound(_amount, 0, type(uint224).max);
        mintNdaoAndVoteLock(_holder, _amount);

        skip((365 days) / 4);

        testRequests.push(
            UnlockRequest({
                index: 0,
                amount: ((_amount / 4) + 1)
            })
        );

        vm.prank(_holder);
        vm.expectRevert(ErrorInvalidUnlockRequest);
        nvt.unlock(testRequests);
    }

    function testFuzz_CannotUnlockMoreThanAvailableInMultipleRequests(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 0, type(uint224).max);
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
        vm.expectRevert(ErrorInvalidUnlockRequest);
        nvt.unlock(testRequests);
    }

    function testFuzz_CannotUnlockMoreThanTwoDepositsOverTwoTimeSpans(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 0, type(uint112).max);
        _amount2 = bound(_amount2, 0, type(uint112).max);

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
        vm.expectRevert(ErrorInvalidUnlockRequest);
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
        _amount = bound(_amount, 1, type(uint224).max);
        mintNdaoAndVoteLock(_holder, _amount);

        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, block.timestamp);

        assertEq(activeIndices.length, 1);
        assertEq(activeIndices[0], 0);
        assertEq(_amountAvailable, 0);
    }

    function testFuzz_AfterOneDepositTimeElapsed(address _holder, uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint224).max);
        mintNdaoAndVoteLock(_holder, _amount);

        uint256 timestamp = block.timestamp + (365 days) / 4;
        uint256[] memory activeIndices = nvt.getActiveDepositIndices(_holder, 0);
        uint256 _amountAvailable = nvt.getTotalAvailableForWithdrawal(_holder, 0, timestamp);

        assertEq(activeIndices.length, 1);
        assertEq(activeIndices[0], 0);
        assertEq(_amountAvailable, _amount / 4);
    }

    function testFuzz_ImmediatelyAfterTwoDeposits(address _holder, uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, 1, type(uint112).max);
        _amount2 = bound(_amount2, 1, type(uint112).max);

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
        _amount1 = bound(_amount1, 1, type(uint112).max);
        _amount2 = bound(_amount2, 1, type(uint112).max);

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
        _amount1 = bound(_amount1, 1, type(uint112).max);
        _amount2 = bound(_amount2, 1, type(uint112).max);

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
        _amount = bound(_amount, 0, type(uint224).max);
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
        _amount1 = bound(_amount1, 1, type(uint112).max);
        _amount2 = bound(_amount2, 1, type(uint112).max);

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
        _amount1 = bound(_amount1, 1, type(uint112).max);
        _amount2 = bound(_amount2, 1, type(uint112).max);

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
