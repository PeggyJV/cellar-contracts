# Sommelier Aave V2 Stablecoin Cellar

Aave V2 Stablecoin Cellar contract for Sommelier Network

## Testing and Development on testnet

### Dependencies

- [nodejs](https://nodejs.org/en/download/) - >=v8, tested with version v14.15.4
- hardhat

Run scripts (fork mainnet):

```bash
npx hardhat --network hardhat run scripts/gasConsumption.test.js

result:

cellar.deposit tx.blockNumber: 13837547, gasUsed: 250646
cellar.swap tx.blockNumber: 13837548, gasUsed: 147989
cellar.multihopSwap tx.blockNumber: 13837549, gasUsed: 139874
cellar.sushiswap tx.blockNumber: 13837550, gasUsed: 132350
cellar.enterStrategy tx.blockNumber: 13837551, gasUsed: 332342
cellar.withdraw tx.blockNumber: 13837556, gasUsed: 372811
cellar.redeemFromAave tx.blockNumber: 13837559, gasUsed: 288590
cellar.rebalance tx.blockNumber: 13837560, gasUsed: 579163
```


```bash
npx hardhat --network hardhat run scripts/swapGasEstimate.test.js

result:

singleSwap 50 USDC -> DAI tx.blockNumber: 13837538, gasUsed: 147655 (22.58 USD)
amountOut: 49.76 USD
multihopSwap 50 USDC -> DAI tx.blockNumber: 13837539, gasUsed: 138647 (21.21 USD)
amountOut: 49.76 USD
sushiSwap 50 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'STF'
multihopSwap 50 USDC -> WETH -> DAI tx.blockNumber: 13837541, gasUsed: 227455 (34.79 USD)
amountOut: 49.71 USD
sushiSwap 50 USDC -> WETH -> DAI tx.blockNumber: 13837542, gasUsed: 185646 (28.39 USD)
amountOut: 49.70 USD
multihopSwap 50 USDC -> USDT -> DAI tx.blockNumber: 13837543, gasUsed: 286167 (43.77 USD)
amountOut: 5.01 USD
sushiSwap 50 USDC -> USDT -> DAI tx.blockNumber: 13837544, gasUsed: 198152 (30.31 USD)
amountOut: 37.70 USD
--------------------------------------
singleSwap 1000 USDC -> DAI tx.blockNumber: 13837545, gasUsed: 167245 (25.58 USD)
amountOut: 994.57 USD
multihopSwap 1000 USDC -> DAI tx.blockNumber: 13837546, gasUsed: 138659 (21.21 USD)
amountOut: 993.52 USD
sushiSwap 1000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'STF'
multihopSwap 1000 USDC -> WETH -> DAI tx.blockNumber: 13837548, gasUsed: 210343 (32.17 USD)
amountOut: 994.20 USD
sushiSwap 1000 USDC -> WETH -> DAI tx.blockNumber: 13837549, gasUsed: 185634 (28.39 USD)
amountOut: 993.87 USD
multihopSwap 1000 USDC -> USDT -> DAI tx.blockNumber: 13837550, gasUsed: 783146 (119.78 USD)
amountOut: 3.99 USD
sushiSwap 1000 USDC -> USDT -> DAI tx.blockNumber: 13837551, gasUsed: 198140 (30.31 USD)
amountOut: 95.14 USD
--------------------------------------
singleSwap 5000 USDC -> DAI tx.blockNumber: 13837552, gasUsed: 201473 (30.82 USD)
amountOut: 4948.82 USD
multihopSwap 5000 USDC -> DAI tx.blockNumber: 13837553, gasUsed: 854270 (130.66 USD)
amountOut: 1023.14 USD
sushiSwap 5000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
multihopSwap 5000 USDC -> WETH -> DAI tx.blockNumber: 13837555, gasUsed: 208355 (31.87 USD)
amountOut: 4970.93 USD
sushiSwap 5000 USDC -> WETH -> DAI tx.blockNumber: 13837556, gasUsed: 185646 (28.39 USD)
amountOut: 4968.24 USD
multihopSwap 5000 USDC -> USDT -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
sushiSwap 5000 USDC -> USDT -> DAI tx.blockNumber: 13837558, gasUsed: 198152 (30.31 USD)
amountOut: 15.46 USD
--------------------------------------
singleSwap 10000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
multihopSwap 10000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
sushiSwap 10000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
multihopSwap 10000 USDC -> WETH -> DAI tx.blockNumber: 13837562, gasUsed: 219017 (33.50 USD)
amountOut: 9941.55 USD
sushiSwap 10000 USDC -> WETH -> DAI tx.blockNumber: 13837563, gasUsed: 185646 (28.39 USD)
amountOut: 9930.89 USD
multihopSwap 10000 USDC -> USDT -> DAI VM Exception while processing transaction: reverted with reason string 'STF'
sushiSwap 10000 USDC -> USDT -> DAI VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
--------------------------------------
singleSwap 50 DAI -> USDC tx.blockNumber: 13837566, gasUsed: 734531 (112.35 USD)
amountOut: 58.41 USD
multihopSwap 50 DAI -> USDC tx.blockNumber: 13837567, gasUsed: 133201 (20.37 USD)
amountOut: 51.16 USD
sushiSwap 50 DAI -> USDC VM Exception while processing transaction: reverted with reason string 'STF'
multihopSwap 50 DAI -> WETH -> USDC tx.blockNumber: 13837569, gasUsed: 205702 (31.46 USD)
amountOut: 49.69 USD
sushiSwap 50 DAI -> WETH -> USDC tx.blockNumber: 13837570, gasUsed: 182455 (27.91 USD)
amountOut: 49.77 USD
--------------------------------------
singleSwap 1000 DAI -> USDC tx.blockNumber: 13837571, gasUsed: 132715 (20.30 USD)
amountOut: 1017.96 USD
multihopSwap 1000 DAI -> USDC tx.blockNumber: 13837572, gasUsed: 163067 (24.94 USD)
amountOut: 1008.29 USD
sushiSwap 1000 DAI -> USDC VM Exception while processing transaction: reverted with reason string 'STF'
multihopSwap 1000 DAI -> WETH -> USDC tx.blockNumber: 13837574, gasUsed: 205702 (31.46 USD)
amountOut: 993.88 USD
sushiSwap 1000 DAI -> WETH -> USDC tx.blockNumber: 13837575, gasUsed: 182455 (27.91 USD)
amountOut: 995.26 USD
--------------------------------------
singleSwap 10000 DAI -> USDC tx.blockNumber: 13837576, gasUsed: 162675 (24.88 USD)
amountOut: 9998.56 USD
multihopSwap 10000 DAI -> USDC tx.blockNumber: 13837577, gasUsed: 368580 (56.37 USD)
amountOut: 3006.58 USD
sushiSwap 10000 DAI -> USDC VM Exception while processing transaction: reverted with reason string 'STF'
multihopSwap 10000 DAI -> WETH -> USDC tx.blockNumber: 13837579, gasUsed: 214396 (32.79 USD)
amountOut: 9938.59 USD
sushiSwap 10000 DAI -> WETH -> USDC VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'

```

Run tests:

```bash
npx hardhat test
```

## Disclaimer

Neither does VolumeFi nor Sommelier manage any portfolios. You must make an independent judgment as to whether to add liquidity to portfolios.
Users of this repo should familiarize themselves with smart contracts to further consider the risks associated with smart contracts before adding liquidity to any portfolios or deployed smart contract. These smart contracts are non-custodial and come with no warranties. VolumeFi does not endorse any pools in any of the smart contracts found in this repo. VolumeFi and Sommelier are not giving you investment advice with this software and neither firm has control of your funds. All our smart contract software is alpha, works in progress and are undergoing daily updates that may result in errors or other issues.
