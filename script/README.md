# Endaoment Scripts

This folder contains utility scripts that can be used to deploy and interact with the Endaoment V2 smart contracts. The
instructions for running the scripts below assume you already have the `foundry` tool installed. See the main repo
`README` files for instructions on `foundry` installation.

Usage overview, in 2 different shell windows run the 2 commands below:

```sh
anvil --fork-url $RPC_URL --fork-block-number 14843823
```

```sh
forge script script/LocalDeploy.s.sol --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast --slow --rpc-url http://127.0.0.1:8545
```

## Configuration / Setup of the LocalDeploy script

In a shell window, start a local instance of the `anvil` Ethereum node software, with the following command:

```sh
anvil --fork-url $RPC_URL --fork-block-number 14843823
```

Note that `--fork-url` is the current Endaoment Alchemy API paid end-point for main-net access.

Note that because LocalDeploy runs on a fork of main-net, it therefore makes use of the main-net USDC contract address
internally.

Note that `--fork-block-number` is an arbitrary recent main-net block from which `anvil` will replicate blockchain
state.

The above command will run a local blockchain node, accessible at the URL `http://127.0.0.1:8545`.

The startup of `anvil` will produce output containing information about the accounts and private keys that are built
into the `anvil` instance. Some of the output will look like this... take note of the "private keys" section, we'll be
making use of that in running the LocalDeploy script.

```
Available Accounts
==================
(0) 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266 (10000 ETH)
(1) 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 (10000 ETH)
(2) 0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc (10000 ETH)
(3) 0x90f79bf6eb2c4f870365e785982e1f101e93b906 (10000 ETH)
(4) 0x15d34aaf54267db7d7c367839aaf71a00a2c6a65 (10000 ETH)
(5) 0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc (10000 ETH)
(6) 0x976ea74026e726554db657fa54763abd0c3a0aa9 (10000 ETH)
(7) 0x14dc79964da2c08b23698b3d3cc7ca32193d9955 (10000 ETH)
(8) 0x23618e81e3f5cdf7f54c3d65f7fbc0abf5b21e8f (10000 ETH)
(9) 0xa0ee7a142d267c1f36714e4a8f75612f20a79720 (10000 ETH)

Private Keys
==================
(0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
(1) 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
(2) 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
(3) 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
(4) 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
(5) 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba
(6) 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e
(7) 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356
(8) 0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97
(9) 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6

```

"Private keys" (0) is associated with "Available Accounts" (0) which will be used as the deploying EOA when the
LocalDeploy script is run.

The LocalDeploy script will deploy the core protocol smart contracts to this node, where they can then be executed by
the Endoament front-end and API via that RPC URL.

### Getting ERC20 tokens for testing

Since we need to ensure our contracts work with tokens outside of ETH, we have to transfer tokens from other accounts
over to our test accounts.

We can do this by impersonating a user in anvil and then calling `transfer` in the format:

```
cast rpc anvil_impersonateAccount $REAL_PERSONS_WALLET
cast send $TOKEN_ADDRESS --from $REAL_PERSONS_WALLET "transfer(address,uint256)(bool)" $DEV_WALLET $AMOUNT_WEI
```

For example, we can transfer DAI to the `0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266` account using the following:

```
export TOKEN_ADDRESS=0x6b175474e89094c44da98b954eedeac495271d0f
export REAL_PERSONS_WALLET=0xaD0135AF20fa82E106607257143d0060A7eB5cBf
export DEV_WALLET=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
export AMOUNT_WEI=50000000000000000000000000

cast rpc anvil_impersonateAccount $REAL_PERSONS_WALLET
cast send $TOKEN_ADDRESS --from $REAL_PERSONS_WALLET "transfer(address,uint256)(bool)" $DEV_WALLET $AMOUNT_WEI
```

and you can check the balance of a token using:

```
cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" $DEV_WALLET
```

Here are some token addresses to make your life easier:

| Name  | Address                                    |
| ----- | ------------------------------------------ |
| USDC: | 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 |
| DAI:  | 0x6b175474e89094c44da98b954eedeac495271d0f |

## Execution of the LocalDeploy script

In a second shell window, the LocalDeploy script can be executed to deploy the Endaoment smart contract to the `anvil`
node via the following command:

```
forge script script/LocalDeploy.s.sol --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast --rpc-url http://127.0.0.1:8545
```

Note that `--private-key` references the private key for account 0 of the `anvil` Ethereum node.

Note that `--rpc-url` points to the `anvil` node as the target for contract deployments.

## Collecting deployed contract addresses from LocalDeploy execution

In order to collect the deployed contract addresses into a JSON file for use in integration testing with the Endaoment
front-end and/or API, the following command can be used in the second shell window:

```
forge script script/LocalDeploy.s.sol --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast --slow --fork-url http://127.0.0.1:8545 --json
```

Because the `forge script` outputs a JSON formatted log when supplied with the `--json` command line argument, the
deployed contract names and addresses can be parsed from that JSON file for use by the Endaoment front-end and/or API.

The `forge script` command will output the name and path of the JSON file as it finishes its execution:

```
ONCHAIN EXECUTION COMPLETE & SUCCESSFUL. Transaction receipts written to "broadcast/LocalDeploy.s.sol/1/run-latest.json"
```

The "contractName" and "contractAddress" keys in each transaction in the array of transactions will contain the desired
information. The snippet below illustrates this.

```
{
  "transactions": [
    {
      "hash": "0x89205089859be61235532bfde2108a38fb7b4a689d402761d432aa6a4568dc1e",
      "type": "CREATE",
      "contractName": "Registry",
      "contractAddress": "0x0xef31027350be2c7439c1b0be022d49421488b72c",
      "tx": {
        "type": "0x02",
```
