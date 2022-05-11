# Endaoment Contracts V2

## Getting Started

This repo is built using [Foundry](https://github.com/gakonst/foundry)

1. [Install Foundry](https://github.com/gakonst/foundry#installation)
1. Install dependencies with `make install`

## Development

- Copy the **.env.template file** to **.env** and replace the `RPC_URL` with your own endpoint.
- Build contracts with `make build`.
- Run tests with `make test`.

### Testing

Currently many tests are fuzz tests, where the fuzzer will generate a value between 0 and the max value of the specified type.

For more information, see the [fuzz testing section of the Foundry book](https://onbjerg.github.io/foundry-book/forge/fuzz-testing.html).

# Contracts

The Endaoment ecosystem uses several contracts to govern the movement of funds between Donor-Advised Funds (DAFs) and organizations:

## `Registry.sol`

The Registry is the center of the contract system. Most of the system is gated by state checks against the Registry. It's the single source of truth for the following questions:

- What roles and permissions are required to access system functionality?
- Is an address an Entity, or some outside contract/EOA?
- What Entity factories, swap wrappers, and portfolios have been approved?
- What is an Entity's donation/transfer/payout fee?
- What is the Endaoment treasury address?

## `lib/auth/EndaomentAuth.sol`

EndaomentAuth is an abstract contract from which contracts in the Endaoment ecosystem inherit. EndaomentAuth access-gates important methods on Registry, Entity, Portfolio, and beyond. As owner, the board can create roles and capabilities to express fine-grained permissions. See [DeployTest.sol:L87](/src/test/utils/DeployTest.sol#L87) for working examples of role and capability definitions. Contracts making use of EndaomentAuth can optionally declare themselves a "special target" at deploy time. See documentation on [`EndaomentAuth:specialTarget`](/src/lib/auth/EndaomentAuth.sol#L35) for more information.

## `EntityFactory.sol`

- see also OrgFundFactory.sol

EntityFactory is an abstract contract from which Entity factories (OrgFundFactory) inherit. Currently, Org and Fund are the only entity types, but as more entity types are added, additional factories will be required to deploy them. EntityFactories must be enabled on the Registry so that they can deploy Entities "inside" the Endaoment system. EntityFactories also facilitate combinations like "deploy and donate" and "deploy, swap, and donate."

## `Entity.sol`

- see also Fund.sol, Org.sol

Entity is an abstract contract from which specific Entity types (Fund, Org) inherit. It's responsible for processing donations, transfers, and payouts for a particular organization or donor-advised fund. Additionally, it can deposit into and redeem from Portfolios. Important Entity methods can only be called by the Entity's manager, or a privileged role in the Endaoment system. While an Entity can receive any token, it primarily "speaks in" USDC, and we provide methods so that an Entity's tokens can be swapped to USDC for use in the system.

## `Portfolio.sol`

- see also portfolios folder

Portfolio is an abstract contract from which specific Portfolio implementations (aave USDC, cUSDC, yearn USDC, and single token portfolios i.e. WBTC) inherit. It borrows concepts from ERC-4626 in that Entities can exchanges assets for shares, but differs in deposit/redeem signature to provide Entities a way to swap into the portfolio asset. Portfolios can have caps, fees on deposit, fees on redemption, and an assets under management fee -- all settable by privileged roles defined in Registry.

## `ISwapWrapper.sol`

- see also swapWrappers folder

ISwapWrapper is an interface to which Endaoment swap wrappers must conform. Swap wrappers allow Entities to swap their USDC for Portfolio assets, Portfolios to swap their assets back to USDC on share redemption, and ERC20 token donations to be swapped into USDC. New swap wrappers can be developed as the system expands to multiple protocols and liquidity providers.

## `NDAO.sol`, `NVT.sol`

NDAO and NVT are ERC20 tokens used for Endaoment governance and participation reward. NDAO can be locked for NVT, which can then be used to signal on an off-chain voting protocol. Once locked, NVT is unlocked over time. In the NVT contract, considerations were made for holders of vesting NDAO tokens; they too can lock their vesting NDAO in exchange for NVT.

## `RollingMerkleDistributor.sol`

There are 2 rolling merkle distributors in the Endaoment system: one each for NDAO and USDC rewards. Users or Entities participating in the system can receive rewards from one or both of these merkle distributors. Rewards are calculated off-chain and formed into a merkle tree so that a privileged role can set a merkle root for reward claim. These distributors can be distinguished from traditional merkle distributors (a la Uniswap) by their rolling claim window. The intention is to give the stakeholder the ability to rollover unclaimed funds from the previous window into the next Merkle root, so users can claim anytime and never "miss" their chance to do so.

## `AtomicClaim.sol`

AtomicClaim is a contract that Org stakeholders can use to claim their reward USDC from the merkle distributor, transferring it to the Org.
