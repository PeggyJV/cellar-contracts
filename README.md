# cellars
Sommelier Ethereum Cellars Work in Progress

## Testing and Development on testnet

### Dependencies
* [nodejs](https://nodejs.org/en/download/) - >=v8, tested with version v14.15.4
* [python3](https://www.python.org/downloads/release/python-368/) from version 3.6 to 3.8, python3-dev
* [brownie](https://github.com/iamdefinitelyahuman/brownie) - tested with version [1.14.6](https://github.com/eth-brownie/brownie/releases/tag/v1.14.6)

The contracts are compiled using [Vyper](https://github.com/vyperlang/vyper), however, installation of the required Vyper versions is handled by Brownie.

### Running the Tests

```bash
brownie test
```

### Extra Tests with Hardhat
You may also see our Hardhat test implementation here: [Hardhat & Remix Readme](extras/hardhat/hardhat.md)