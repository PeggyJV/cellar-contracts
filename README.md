# cellars
Sommelier Ethereum Cellars Work in Progress

## Testing and Development on testnet

### Dependencies
* [nodejs](https://nodejs.org/en/download/) - >=v8, tested with version v14.15.4
* [python3](https://www.python.org/downloads/release/python-368/) from version 3.6 to 3.8, python3-dev
* [brownie](https://github.com/iamdefinitelyahuman/brownie) - tested with version [1.14.6](https://github.com/eth-brownie/brownie/releases/tag/v1.14.6)

The contracts are compiled using [Vyper](https://github.com/vyperlang/vyper), however, installation of the required Vyper versions is handled by Brownie.

### Brownie PM setting
```bash
brownie pm install OpenZeppelin/openzeppelin-contracts@3.4.1-solc-0.7-2
brownie pm install Uniswap/uniswap-v3-core@1.0.0
brownie pm install Uniswap/uniswap-v3-periphery@1.0.0
```

### Python package path dependencies
After that, replace all Dependencies in `~/.brownie/packages/Uniswap`

`@uniswap/v3-core/contracts` -> `Uniswap/uniswap-v3-core@1.0.0/contracts`

`@openzeppelin/contracts` -> `OpenZeppelin/openzeppelin-contracts@3.4.1-solc-0.7-2/contracts`


### Running the Tests

```bash
brownie test
```