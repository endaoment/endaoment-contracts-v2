# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

install:
	forge install

build:
	forge build

clean:
	forge clean

test:
	forge test --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --no-match-path "*.fork.t.sol" --match-path "*.t.sol" && \
	forge test --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --fork-url "${RPC_URL}" --fork-block-number 14500000 --match-path "*.fork.t.sol" --no-match-path  "{*CurveWrapper.fork.t.sol,*MultiSwapWrapper.fork.t.sol}" && \
	forge test --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --fork-url "${RPC_URL}" --fork-block-number 14787296 --match-path "{*CurveWrapper.fork.t.sol,*MultiSwapWrapper.fork.t.sol}"

snapshot:
	forge snapshot --match-path src/test/Gas.sol --fork-url "${RPC_URL}" --fork-block-number 14500000
