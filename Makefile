# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

install:
	forge install

build:
	forge build

test:
	forge test --no-match-path "*.fork.t.sol" && forge test --fork-url "${RPC_URL}" --fork-block-number 14500000 --match-path "*.fork.t.sol"
