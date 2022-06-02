# Sommelier Cellar Contracts • [![tests](https://github.com/PeggyJV/cellar-contracts/actions/workflows/tests.yml/badge.svg)](https://github.com/PeggyJV/cellar-contracts/actions/workflows/tests.yml) [![lints](https://github.com/PeggyJV/cellar-contracts/actions/workflows/lints.yml/badge.svg)](https://github.com/PeggyJV/cellar-contracts/actions/workflows/lints.yml) ![license](https://img.shields.io/github/license/PeggyJV/cellar-contracts)

Cellar contracts for Sommelier Network

### Getting Started

- Use Foundry:

```bash
forge install
forge test
```

- Use Hardhat:

```bash
npm install
npx hardhat test
```

### Development

- Run tests with either Hardhat or Foundry:

```bash
forge test
# or
npx hardhat test
```

- Use Hardhat's task framework:

```bash
npx hardhat example
```

- Install libraries with Foundry which work with Hardhat:

```bash
forge install rari-capital/solmate # Already in this repo, just an example
```

### Notes

Whenever you install new libraries using Foundry, make sure to update your `remappings.txt` file by running `forge remappings > remappings.txt`. This is required because we use `hardhat-preprocessor` and the `remappings.txt` file to allow Hardhat to resolve libraries you install with Foundry.
