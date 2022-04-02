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

singleSwap 50 USDC -> DAI tx.blockNumber: 13837538, gasUsed: 147688 (22.59 USD)
amountOut: 49.76 USD
multihopSwap 50 USDC -> DAI tx.blockNumber: 13837539, gasUsed: 138680 (21.21 USD)
amountOut: 49.76 USD
sushiSwap 50 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'STF'
curveSwap 50 USDC -> DAI tx.blockNumber: 13837541, gasUsed: 152559 (23.33 USD)
amountOut: 49.98 USD
multihopSwap 50 USDC -> WETH -> DAI tx.blockNumber: 13837542, gasUsed: 227488 (34.79 USD)
amountOut: 49.71 USD
sushiSwap 50 USDC -> WETH -> DAI tx.blockNumber: 13837543, gasUsed: 185679 (28.40 USD)
amountOut: 49.70 USD
multihopSwap 50 USDC -> USDT -> DAI tx.blockNumber: 13837544, gasUsed: 286200 (43.77 USD)
amountOut: 5.01 USD
sushiSwap 50 USDC -> USDT -> DAI tx.blockNumber: 13837545, gasUsed: 198185 (30.31 USD)
amountOut: 37.70 USD
--------------------------------------
singleSwap 1000 USDC -> DAI tx.blockNumber: 13837546, gasUsed: 167278 (25.59 USD)
amountOut: 994.57 USD
multihopSwap 1000 USDC -> DAI tx.blockNumber: 13837547, gasUsed: 138692 (21.21 USD)
amountOut: 993.52 USD
sushiSwap 1000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'STF'
curveSwap 1000 USDC -> DAI tx.blockNumber: 13837549, gasUsed: 152549 (23.33 USD)
amountOut: 999.63 USD
multihopSwap 1000 USDC -> WETH -> DAI tx.blockNumber: 13837550, gasUsed: 210376 (32.18 USD)
amountOut: 994.20 USD
sushiSwap 1000 USDC -> WETH -> DAI tx.blockNumber: 13837551, gasUsed: 185667 (28.40 USD)
amountOut: 993.87 USD
multihopSwap 1000 USDC -> USDT -> DAI tx.blockNumber: 13837552, gasUsed: 783179 (119.79 USD)
amountOut: 3.99 USD
sushiSwap 1000 USDC -> USDT -> DAI tx.blockNumber: 13837553, gasUsed: 198173 (30.31 USD)
amountOut: 95.14 USD
--------------------------------------
singleSwap 5000 USDC -> DAI tx.blockNumber: 13837554, gasUsed: 201506 (30.82 USD)
amountOut: 4948.82 USD
multihopSwap 5000 USDC -> DAI tx.blockNumber: 13837555, gasUsed: 854303 (130.67 USD)
amountOut: 1023.14 USD
sushiSwap 5000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
curveSwap 5000 USDC -> DAI tx.blockNumber: 13837557, gasUsed: 152559 (23.33 USD)
amountOut: 4998.16 USD
multihopSwap 5000 USDC -> WETH -> DAI tx.blockNumber: 13837558, gasUsed: 208388 (31.87 USD)
amountOut: 4970.93 USD
sushiSwap 5000 USDC -> WETH -> DAI tx.blockNumber: 13837559, gasUsed: 185679 (28.40 USD)
amountOut: 4968.24 USD
multihopSwap 5000 USDC -> USDT -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
sushiSwap 5000 USDC -> USDT -> DAI tx.blockNumber: 13837561, gasUsed: 198185 (30.31 USD)
amountOut: 15.46 USD
--------------------------------------
singleSwap 10000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
multihopSwap 10000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
sushiSwap 10000 USDC -> DAI VM Exception while processing transaction: reverted with reason string 'SPL'
curveSwap 10000 USDC -> DAI tx.blockNumber: 13837565, gasUsed: 152559 (23.33 USD)
amountOut: 9996.33 USD
multihopSwap 10000 USDC -> WETH -> DAI VM Exception while processing transaction: reverted with reason string 'STF'
sushiSwap 10000 USDC -> WETH -> DAI VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
multihopSwap 10000 USDC -> USDT -> DAI VM Exception while processing transaction: reverted with reason string 'STF'
sushiSwap 10000 USDC -> USDT -> DAI VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
--------------------------------------
singleSwap 50 DAI -> USDC tx.blockNumber: 13837570, gasUsed: 734564 (112.35 USD)
amountOut: 58.41 USD
multihopSwap 50 DAI -> USDC tx.blockNumber: 13837571, gasUsed: 133234 (20.38 USD)
amountOut: 51.16 USD
sushiSwap 50 DAI -> USDC VM Exception while processing transaction: reverted with reason string 'STF'
curveSwap 50 DAI -> USDC tx.blockNumber: 13837573, gasUsed: 152314 (23.30 USD)
amountOut: 49.99 USD
multihopSwap 50 DAI -> WETH -> USDC tx.blockNumber: 13837574, gasUsed: 205745 (31.47 USD)
amountOut: 49.69 USD
sushiSwap 50 DAI -> WETH -> USDC tx.blockNumber: 13837575, gasUsed: 182488 (27.91 USD)
amountOut: 49.73 USD
--------------------------------------
singleSwap 1000 DAI -> USDC tx.blockNumber: 13837576, gasUsed: 132748 (20.30 USD)
amountOut: 1017.96 USD
multihopSwap 1000 DAI -> USDC tx.blockNumber: 13837577, gasUsed: 163100 (24.95 USD)
amountOut: 1008.29 USD
sushiSwap 1000 DAI -> USDC VM Exception while processing transaction: reverted with reason string 'STF'
curveSwap 1000 DAI -> USDC tx.blockNumber: 13837579, gasUsed: 152314 (23.30 USD)
amountOut: 999.77 USD
multihopSwap 1000 DAI -> WETH -> USDC tx.blockNumber: 13837580, gasUsed: 205745 (31.47 USD)
amountOut: 993.84 USD
sushiSwap 1000 DAI -> WETH -> USDC tx.blockNumber: 13837581, gasUsed: 182488 (27.91 USD)
amountOut: 994.52 USD
--------------------------------------
singleSwap 10000 DAI -> USDC tx.blockNumber: 13837582, gasUsed: 162708 (24.89 USD)
amountOut: 9998.56 USD
multihopSwap 10000 DAI -> USDC tx.blockNumber: 13837583, gasUsed: 368613 (56.38 USD)
amountOut: 3006.58 USD
sushiSwap 10000 DAI -> USDC VM Exception while processing transaction: reverted with reason string 'STF'
curveSwap 10000 DAI -> USDC tx.blockNumber: 13837585, gasUsed: 152324 (23.30 USD)
amountOut: 9997.67 USD
multihopSwap 10000 DAI -> WETH -> USDC VM Exception while processing transaction: reverted with reason string 'STF'
sushiSwap 10000 DAI -> WETH -> USDC VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'

```

```bash
npx hardhat --network hardhat run scripts/rebalanceGasEstimate.test.js

result:
aUSDC balance: BigNumber { value: "10000000009" }
aDAI balance: BigNumber { value: "0" }
totalAssets: BigNumber { value: "10000000009" }
--------------------------------------
cellar.rebalance tx.blockNumber: 13837543, gasUsed: 1495451 (228.73 USD)
aUSDC balance: BigNumber { value: "0" }
aDAI balance: BigNumber { value: "8059567655797439381374" }
totalAssets: BigNumber { value: "8059567655797439381374" }
--------------------------------------
cellar.rebalance tx.blockNumber: 13837544, gasUsed: 1275334 (195.06 USD)
aUSDC balance: BigNumber { value: "8107247329" }
aDAI balance: BigNumber { value: "0" }
totalAssets: BigNumber { value: "9951309496" }
--------------------------------------
cellar.rebalanceByCurve tx.blockNumber: 13837545, gasUsed: 543008 (83.05 USD)
aUSDC balance: BigNumber { value: "0" }
aDAI balance: BigNumber { value: "8105301030616713172921" }
totalAssets: BigNumber { value: "8105301030616713172921" }
--------------------------------------
cellar.rebalanceByCurve tx.blockNumber: 13837546, gasUsed: 545205 (83.39 USD)
aUSDC balance: BigNumber { value: "8100675318" }
aDAI balance: BigNumber { value: "0" }
totalAssets: BigNumber { value: "9944737485" }

```

Run tests:

```bash
npx hardhat test
```

## Disclaimer

Neither does VolumeFi nor Sommelier manage any portfolios. You must make an independent judgment as to whether to add liquidity to portfolios.
Users of this repo should familiarize themselves with smart contracts to further consider the risks associated with smart contracts before adding liquidity to any portfolios or deployed smart contract. These smart contracts are non-custodial and come with no warranties. VolumeFi does not endorse any pools in any of the smart contracts found in this repo. VolumeFi and Sommelier are not giving you investment advice with this software and neither firm has control of your funds. All our smart contract software is alpha, works in progress and are undergoing daily updates that may result in errors or other issues.
