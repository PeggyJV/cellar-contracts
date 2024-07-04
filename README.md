# Sommelier Cellar Contracts • [![tests](https://github.com/PeggyJV/cellar-contracts/actions/workflows/tests.yml/badge.svg)](https://github.com/PeggyJV/cellar-contracts/actions/workflows/tests.yml) [![lints](https://github.com/PeggyJV/cellar-contracts/actions/workflows/lints.yml/badge.svg)](https://github.com/PeggyJV/cellar-contracts/actions/workflows/lints.yml) ![license](https://img.shields.io/github/license/PeggyJV/cellar-contracts)

Cellar contracts for the Sommelier Network.


### Documentation

- [UI guidelines](./docs/cellar_ui.md) Building UI flows with Cellars
- [Permissions](./docs/permissions.md) Permissions in Cellars
- [Using Cellars](./docs/using_cellars.md) Using the Cellars Smart Contracts as a strategist
- [Fees](./docs/fees.md) How fees work for the strategist and the platform
- [Positions](./docs/positions.md) How positions are created and managed
- [Adapaters](./docs/adapters.md) How adapters are created and managed

### Development

**Getting Started**

Before attempting to setup the repo, first make sure you have Foundry installed and updated, which can be done [here](https://github.com/foundry-rs/foundry#installation).

**Building**

Install Foundry dependencies and build the project.

```bash
forge build
```

To install new libraries.

```bash
forge install <GITHUB_USER>/<REPO>
```

Example

```bash
forge install transmissions11/solmate
```

Whenever you install new libraries using Foundry, make sure to update your `remappings.txt` file.

**Testing**

Before running test, rename `sample.env` to `.env`, and add your mainnet RPC. If you want to deploy any contracts, you will need that networks RPC, a Private Key, and an Etherscan key(if you want foundry to verify the contracts).
Note in order to run tests against forked mainnet, your RPC must be an archive node. My favorite archive node is [Alchemy](https://www.alchemy.com).

Run tests with Foundry:

```bash
npm run forkTest
```
