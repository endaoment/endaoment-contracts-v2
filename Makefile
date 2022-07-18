# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

install:
	forge install

build:
	forge build

clean:
	forge clean

local:
	anvil --fork-url "${RPC_URL}" --fork-block-number 15892404

# test will create broadcast directory for deployment/migration testing if it doesn't exist
test: create-broadcast-folder
	forge test

create-broadcast-folder:
	mkdir -p broadcast

# Don't worry, the PK used here is a well known PK of the test mnemonic ;)
local-deploy:
	forge script script/LocalDeploy.s.sol --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast  --rpc-url http://127.0.0.1:8545
