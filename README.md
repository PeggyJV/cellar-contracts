# cellars
Sommelier Ethereum Cellars Work in Progress

## Testing and Development on testnet

### Dependencies
* [nodejs](https://nodejs.org/en/download/) - >=v8, tested with version v14.15.4
* [python3](https://www.python.org/downloads/release/python-368/) from version 3.6 to 3.8, python3-dev
* [brownie](https://github.com/iamdefinitelyahuman/brownie) - tested with version [1.14.6](https://github.com/eth-brownie/brownie/releases/tag/v1.14.6)
* ganache-cli

The contracts are compiled using [Vyper](https://github.com/vyperlang/vyper), however, installation of the required Vyper versions is handled by Brownie.

Run Ganache-cli mainnet-fork environment

```bash
ganache-cli --fork https://mainnet.infura.io/v3/#{YOUR_INFURA_KEY} -p 7545
```

Add local network setting to brownie

```bash
brownie networks add Development local host=http://127.0.0.1 accounts=10 evm_version=istanbul fork=mainnet port=7545 mnemonic=brownie cmd=ganache-cli timeout=300
```

Deploy on local ganache-cli network

```bash
brownie run scripts/deploy.py --network local
```

### Running the Tests
```bash
brownie test
```

### Get input amount ratio
```bash
brownie run scripts/check_input_ratio.py
```
If this amount is `division by zero` or `0`, only one token exists in the cellar.


### Tests Suite Files
|Test | Description | Expected Failures | File | 
| --- | --- | --- | --- |
|Add liquidity to the Cellar Test | - Test add liquidity using 1 ETH and 3,000 USDC 3 times for 2 users and compare their balances.<br />- Test add liquidity using 1 WETH and 3,000 USDC 3 times for 2 users and compare their balances. | Their balances should be the same. Otherwise, the test is failure | test_00_add_liquidity.py |
|Transfer liquidity | Test transfer and approve liquidity after adding liquidity using 1 ETH and 3,000 USDC 3 times. | Approve / Transfer / TransferFrom should work as a standard ERC20. Otherwise, the test is failure. | test_01_transfer.py |
|Remove liquidity | Test remove 1/3 liquidity in Uniswap version 3 after adding liquidity using 1 ETH and 3,000 USDC 3 times and compare to decreased balance. | Decreased balance should be the same as the balance for removed liquidity. | test_02_remove_liquidity.py |
|Reinvest liquidity | Test reinvest after adding liquidity using 1 ETH and 3,000 USDC 3 times, confirm account balance is empty after removing liquidity. | The account balance should be empty. | test_03_reinvest.py |
|Rebalance liquidity | Test rebalance after adding liquidity using 1 ETH and 3,000 USDC 3 times, confirm balance of account is 0 after rebalance and removing liquidity. | The account balance should be empty. | test_04_rebalance.py |
|Weight Management | Test liquidities of NFLP in the contract after adding liquidity using 1 ETH and 1,000 USDC, 1 ETH and 5,000 USDC. | The liquidities' ratio should be the approximately same as weight. Accuracy is accurater than 1 millionth | test_05_weight.py |


### Extra Tests with Hardhat
You may also see our Hardhat test implementation here: [Hardhat & Remix Readme](extras/hardhat/hardhat.md)
