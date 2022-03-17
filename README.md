# Endaoment Contracts V2

## Getting Started

This repo is built using [Foundry](https://github.com/gakonst/foundry)

1. [Install Foundry](https://github.com/gakonst/foundry#installation)
1. Install dependencies with `forge install`

## Development

- Build contracts with `forge build`
- Run tests with `forge test`

### Testing

Currently many tests are fuzz tests, where the fuzzer will generate a value between 0 and the max value of the specified type.

For more information, see the [fuzz testing section of the Foundry book](https://onbjerg.github.io/foundry-book/forge/fuzz-testing.html).
