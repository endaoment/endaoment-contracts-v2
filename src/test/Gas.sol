// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import "./Registry.t.sol";
import "./OrgFundFactory.t.sol";
import "./Entity.t.sol";
import "./NVT.t.sol";
import "./RollingMerkleDistributor.t.sol";
import "./SingleTokenPortfolio.t.sol";
import "./CompoundUSDCPortfolio.fork.t.sol";
import "./YearnUSDCPortfolio.fork.t.sol";

// Deploy Orgs

contract ConcreteFactoryOrg is OrgFundFactoryDeployOrgTest {
    bytes32 _orgId = "1234-5678";
    bytes32 _salt = keccak256("salt");
    address _sender = address(0xd00dad);
    uint256 _amount = 186.821698 ether;

    function test_FactoryDeployOrg() public {
        testFuzz_DeployOrg(_orgId, _salt);
    }

    function test_FactoryDeployOrgAndDonate() public {
        testFuzz_DeployOrgAndDonate(_orgId, _salt, _sender, _amount);
    }

    function test_FactoryDeployOrgSwapAndDonate() public {
        testFuzz_DeployOrgSwapAndDonate(_orgId, _salt, _sender, _amount, 730 ether);
    }
}

// Deploy Funds

contract ConcreteFactoryFund is OrgFundFactoryDeployFundTest {
    address _manager = address(0xbadface);
    bytes32 _salt = keccak256("sea salt");
    address _sender = address(0xdecea5edbeef);
    uint256 _amount = 2.2 ether;

    function test_FactoryDeployFund() public {
        testFuzz_DeployFund(_manager, _salt);
    }

    function test_FactoryDeployFundAndDonate() public {
        testFuzz_DeployFundAndDonate(_manager, _salt, _sender, _amount);
    }

    function test_FactoryDeployFundSwapAndDonate() public {
        testFuzz_DeployFundSwapAndDonate(_manager, _salt, _sender, _amount, 2847 ether);
    }
}

// Entity Interactions

contract ConcreteOrgInteractions is OrgTokenTransactionTest {
    function test_EntityDonate() public {
        testFuzz_DonateSuccess(address(0xab), 1000, 5, true);
    }

    function test_EntityDonateWithOverrides() public {
        testFuzz_DonateWithOverridesSuccess(address(0xab), 1000, 5, true);
    }

    function test_EntityPayout() public {
        testFuzz_PayoutSuccess(address(0xab), 5000, 5, 1, true);
    }

    function test_EntityPayoutWithOverrides() public {
        testFuzz_PayoutWithOverridesSuccess(address(0xab), 5000, 5, 1, true);
    }

    function test_EntityTransfer() public {
        testFuzz_TransferSuccess(address(0xab), 5000, 5, address(0xcd), 1);
    }

    function test_EntityTransferWithSenderOverride() public {
        testFuzz_TransferWithSenderOverrideSuccess(address(0xab), 5000, 5, address(0xcd), 1);
    }

    function test_EntityTransferWithReceiverOverride() public {
        testFuzz_TransferWithReceiverOverrideSuccess(address(0xab), 5000, 5, address(0xcd), 1);
    }

    function test_EntityReconcileBalance() public {
        testFuzz_ReconcileBalanceSuccess(address(0xab), 5000, 500, 5);
    }

    function test_EntityReconcileBalanceWithOverrides() public {
        testFuzz_ReconcileBalanceWithOverrideSuccess(address(0xab), 5000, 500, 5);
    }
}

contract ConcreteFundInteractions is FundTokenTransactionTest {
    function test_EntityDonate() public {
        testFuzz_DonateSuccess(address(0xab), 1000, 5, true);
    }

    function test_EntityDonateWithOverrides() public {
        testFuzz_DonateWithOverridesSuccess(address(0xab), 1000, 5, true);
    }

    function test_EntityPayout() public {
        testFuzz_PayoutSuccess(address(0xab), 5000, 5, 1, true);
    }

    function test_EntityPayoutWithOverrides() public {
        testFuzz_PayoutWithOverridesSuccess(address(0xab), 5000, 5, 1, true);
    }

    function test_EntityTransfer() public {
        testFuzz_TransferSuccess(address(0xab), 5000, 5, address(0xcd), 1);
    }

    function test_EntityTransferWithSenderOverride() public {
        testFuzz_TransferWithSenderOverrideSuccess(address(0xab), 5000, 5, address(0xcd), 1);
    }

    function test_EntityTransferWithReceiverOverride() public {
        testFuzz_TransferWithReceiverOverrideSuccess(address(0xab), 5000, 5, address(0xcd), 1);
    }

    function test_EntityReconcileBalance() public {
        testFuzz_ReconcileBalanceSuccess(address(0xab), 5000, 500, 5);
    }

    function test_EntityReconcileBalanceWithOverrides() public {
        testFuzz_ReconcileBalanceWithOverrideSuccess(address(0xab), 5000, 500, 5);
    }
}

// NVT

contract ConcreteNVTVoteLock is VoteLock {

    function test_NVTVoteLock() public {
        testFuzz_NdaoHolderCanVoteLockNvt(address(0xc0ffeec0ded), 4.26 ether);
    }
}

contract ConcreteNVTUnlock is Unlock {
    address _holder = address(0xbeefc0ffee);
    uint256 _amount = 11.6 ether;

    function test_NVTUnlockAll() public {
        testFuzz_UnlockAllAfterYear(_holder, _amount);
    }

    function test_NVTUnlockPartial() public {
        testFuzz_UnlockOneQuarterAfterQuarter(_holder, _amount);
    }

    function test_NVTUnlockTwoDeposits() public {
        testFuzz_UnlockTwoDeposits(_holder, _amount, _amount + 1.1 ether);
    }
}

contract ConcreteNVTUnlockVested is UnlockVested {
    address _holder = address(0xbabb1e);
    uint256 _amount = 8.3 ether;
    uint256 _period = 2 * 365 days;

    function test_NVTUnlockVestedFull() public {
        testFuzz_VesteeCanUnlockAllAtFullVest(_holder, _amount, _period);
    }

    function test_NVTUnlockedVestedPartial() public {
        testFuzz_VesteeUnlockQuarterAfterQuarter(_holder, _amount);
    }
}

// Rolling Merkle Distributor

contract ConcreteMerkleRollover is Rollover {

    function test_MerkleRollover() public {
        testFuzz_CanRolloverTheWindow(keccak256("root"), 7 days, 1);
    }
}

contract ConcreteMerkleClaim is Claim {
    address _claimant = address(0xdadb0d);
    uint256 _amount = 3.62 ether;
    address _claimant2 = address(0xc01dc0c0a);
    uint256 _amount2 = 97.314 ether;

    function test_MerkleClaim() public {
        testFuzz_CanMakeClaimWithBigTree(_claimant, _amount, 0x5eed);
    }

    function test_MerkleTwoClaims() public {
        testFuzz_CanMakeTwoClaims(_claimant, _amount, _claimant2, _amount2);
    }
}

// Single Token Portfolio

contract ConcretePrtfSTPConstructor is STPConstructor {
    string _name = "A Token";
    string _symbol = "ATOK";
    uint8 _decimals = 18;
    uint256 _cap = 500000000000;
    uint256 _depositFee = 50;
    uint256 _redemptionFee = 50;

    function test_STPConstructor () public {
        testFuzz_Constructor(_name, _symbol,_decimals, _cap, _depositFee, _redemptionFee);
    }
}

contract ConcretePrtfSTPSetCap is STPSetCap {
    uint _actor = 1;
    uint _cap = 50000000;

    function test_SetCap() public {
        testFuzz_SetCap(_actor, _cap);
    }
}

contract ConcretePrtfSTPSetDepositFee is STPSetDepositFee {
    uint _actor = 0;
    uint256 _fee = 50;

    function test_SetDepositFee() public {
        testFuzz_SetDepositFee(_actor, _fee);
    }
}

contract ConcretePrtfSTPSetRedemptionFee is STPSetRedemptionFee {
    uint _actor = 1;
    uint256 _fee = 50;

    function test_SetRedemptionFee() public {
        testFuzz_SetRedemptionFee(_actor, _fee);
    }
}

contract ConcretePrtfSTPExchangeRateConvertMath is STPExchangeRateConvertMath {
    uint256 _exchangeRate = Math.WAD / 100;
    uint256 _amount = 5;

    function test_convertToShares() public {
        testFuzz_convertToShares(_exchangeRate, _amount);
    }

    function test_convertToAssets() public {
        testFuzz_convertToShares(_exchangeRate, _amount);
    }
}

contract ConcretePrtfSTPDeposit is STPDeposit {
    uint256 _amount = 500000;
    uint256 _depositFee = 5;
    uint _actor = 1;

    function test_DepositSuccess() public {
        testFuzz_DepositSuccess(_amount, _depositFee, _actor);
    }
}

contract ConcretePrtfSTPDepositRedeem is STPDepositRedeem {
    uint256 _amountSwapDeposit = 20000;
    uint256 _amountSwapRedemption = 20000;
    uint256 _redemptionFee = 50;
    uint8 _actor = 1;

    function test_DepositRedeemFeeSuccess() public {
        testFuzz_DepositRedeemFeeSuccess(_amountSwapDeposit, _amountSwapRedemption, _redemptionFee, _actor);
    }
}

contract ConcretePrtfSTPIntegrationTest is STPIntegrationTest {
    function test_IntegrationTest() public {
        test_Integration();
    }
}

contract ConcretePrtfSTPCallAsPortfolioTest is STPCallAsPortfolioTest {
    address _receiver = address(0xab);
    uint256 _amount = 500;

    function test_CanCallAsPortfolio() public {
        testFuzz_CanCallAsPortfolio(_receiver, _amount);
    }

    function test_CallAsPortfolioToSendETH() public {
        testFuzz_CallAsPortfolioToSendETH(payable(_receiver), _amount);
    }

    function test_CallAsPortfolioToForwardETH() public {
        testFuzz_CallAsPortfolioToForwardETH(payable(_receiver), _amount);
    }
}

contract ConcretePrtfCUPIntegrationTest is CUPIntegrationTest {
    function test_IntegrationTest() public {
        test_Integration();
    }
}

contract ConcretePrtfYUPIntegrationTest is YUPIntegrationTest {
    function test_IntegrationTest() public {
        test_Integration();
    }
}
