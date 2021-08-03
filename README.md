# cellars
Sommelier Ethereum Cellars Work in Progress

## Testing and Development on testnet

### Dependencies
* [nodejs](https://nodejs.org/en/download/) - >=v8, tested with version v14.15.4
* [python3](https://www.python.org/downloads/release/python-368/) from version 3.6 to 3.8, python3-dev
* [brownie](https://github.com/iamdefinitelyahuman/brownie) - tested with version [1.14.6](https://github.com/eth-brownie/brownie/releases/tag/v1.14.6)
* ganache-cli

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


### Libraries Used
|Library Name | Library Description | Source URL or additional documentation |
| --- | --- | --- |
|TickMath | Uniswap Math library for computing sqrt prices from ticks and vice versa. Computes sqrt price for ticks of size 1.0001, i.e. sqrt(1.0001^tick) as fixed point Q64.96 numbers. Supports prices between 2**-128 and 2**128 | [Uniswap v3 Core](https://github.com/Uniswap/uniswap-v3-core/blob/main/contracts/libraries/TickMath.sol) | 
|LiquidityAmounts | Liquidity amount functions provides functions for computing liquidity amounts from token amounts and prices | [Uniswap v3 periphery](https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/libraries/LiquidityAmounts.sol) | 
|SafeMath | Zeppelin Solidity Library for Math operations with safety checks throws on error| [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) |
|Address | Collection of functions related to the address type. Returns true if account is a contract.| [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.1-solc-0.7-2/contracts/utils/Address.sol) | 
|SafeERC20 | Zeppelin Solidity wrapper around the interface that eliminates the need to handle boolean return| [OpenZeppelin](https://docs.openzeppelin.com/contracts/3.x/api/token/erc20) | 
|FixedPoint96 | A library for handling binary fixed point numbers | [Uniswap Core](https://docs.uniswap.org/protocol/reference/core/libraries/FixedPoint96) |
|FullMath | Contains 512-bit math functions. Facilitates multiplication and division that can have overflow of an intermediate value without any loss of precision. Handles "phantom overflow" i.e., allows multiplication and division where an intermediate value overflows 256 bits | [Uniswap libraries](https://github.com/Uniswap/uniswap-lib/blob/master/contracts/libraries/FullMath.sol) | 


## External functions
| Function Name | Parameters |
| --- | --- |
|transfer|address recipient, uint256 amount|
|approve|address spender, uint256 amount|
|transferFrom|address sender,address recipient,uint256 amount|
|addLiquidityForUniV3|CellarAddParams calldata cellarParams|
|addLiquidityEthForUniV3|CellarAddParams calldata cellarParams|
|removeLiquidityEthFromUniV3|CellarRemoveParams calldata cellarParams|
|removeLiquidityFromUniV3|CellarRemoveParams calldata cellarParams|
|reinvest||
|rebalance|CellarTickInfo[] memory _cellarTickInfo|
|setValidator|address _validator, bool value|
|transferOwnership|address, newOwner|
|setFee|uint16, newFee|
|owner||
|name||
|symbol||
|decimals||
|totalSupply||
|balanceOf|address account|
|allowance|address owner_, address spender|

## Internal functions
The internal functions are taken from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.1-solc-0.7-2/contracts/token/ERC20/ERC20.sol
Common ERC-20 interfaces. Please use as reference.