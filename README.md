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

singleSwap 50 usdc -> dai tx.blockNumber: 13837541, gasUsed: 147611 (22.58 USD)
amountOut: 49.76 USD
multihopSwap 50 usdc -> dai tx.blockNumber: 13837542, gasUsed: 138609 (21.20 USD)
amountOut: 49.76 USD
sushiSwap 50 usdc -> dai tx.blockNumber: 13837543, gasUsed: 130515 (19.96 USD)
amountOut: 49.75 USD
multihopSwap 50 usdc -> eth -> dai tx.blockNumber: 13837544, gasUsed: 227417 (34.78 USD)
amountOut: 49.71 USD
sushiSwap 50 usdc -> eth -> dai VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
multihopSwap 50 usdc -> usdt -> dai tx.blockNumber: 13837546, gasUsed: 286129 (43.76 USD)
amountOut: 5.01 USD
sushiSwap 50 usdc -> usdt -> dai VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
--------------------------------------
singleSwap 1000 usdc -> dai tx.blockNumber: 13837548, gasUsed: 167191 (25.57 USD)
amountOut: 994.52 USD
multihopSwap 1000 usdc -> dai tx.blockNumber: 13837549, gasUsed: 138615 (21.20 USD)
amountOut: 993.47 USD
sushiSwap 1000 usdc -> dai tx.blockNumber: 13837550, gasUsed: 137129 (20.97 USD)
amountOut: 992.42 USD
multihopSwap 1000 usdc -> eth -> dai tx.blockNumber: 13837551, gasUsed: 210305 (32.17 USD)
amountOut: 994.20 USD
sushiSwap 1000 usdc -> eth -> dai VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
multihopSwap 1000 usdc -> usdt -> dai tx.blockNumber: 13837553, gasUsed: 783108 (119.78 USD)
amountOut: 3.99 USD
sushiSwap 1000 usdc -> usdt -> dai VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
--------------------------------------
singleSwap 5000 usdc -> dai tx.blockNumber: 13837555, gasUsed: 259309 (39.66 USD)
amountOut: 4926.46 USD
multihopSwap 5000 usdc -> dai tx.blockNumber: 13837556, gasUsed: 796271 (121.79 USD)
amountOut: 3.43 USD
sushiSwap 5000 usdc -> dai VM Exception while processing transaction: reverted with reason string 'SPL'
multihopSwap 5000 usdc -> eth -> dai tx.blockNumber: 13837558, gasUsed: 208317 (31.86 USD)
amountOut: 4970.93 USD
sushiSwap 5000 usdc -> eth -> dai VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
multihopSwap 5000 usdc -> usdt -> dai VM Exception while processing transaction: reverted with reason string 'SPL'
sushiSwap 5000 usdc -> usdt -> dai VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
--------------------------------------
singleSwap 10000 usdc -> dai VM Exception while processing transaction: reverted with reason string 'SPL'
multihopSwap 10000 usdc -> dai VM Exception while processing transaction: reverted with reason string 'SPL'
sushiSwap 10000 usdc -> dai VM Exception while processing transaction: reverted with reason string 'SPL'
multihopSwap 10000 usdc -> eth -> dai tx.blockNumber: 13837565, gasUsed: 218979 (33.49 USD)
amountOut: 9941.55 USD
sushiSwap 10000 usdc -> eth -> dai VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
multihopSwap 10000 usdc -> usdt -> dai VM Exception while processing transaction: reverted with reason string 'SPL'
sushiSwap 10000 usdc -> usdt -> dai VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
--------------------------------------
singleSwap 50 dai -> usdc tx.blockNumber: 13837569, gasUsed: 734487 (112.34 USD)
amountOut: 58.41 USD
multihopSwap 50 dai -> usdc tx.blockNumber: 13837570, gasUsed: 133163 (20.37 USD)
amountOut: 51.16 USD
sushiSwap 50 dai -> usdc tx.blockNumber: 13837571, gasUsed: 132675 (20.29 USD)
amountOut: 51.14 USD
multihopSwap 50 dai -> eth -> usdc tx.blockNumber: 13837572, gasUsed: 205664 (31.46 USD)
amountOut: 49.69 USD
sushiSwap 50 dai -> eth -> usdc VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
--------------------------------------
singleSwap 1000 dai -> usdc tx.blockNumber: 13837574, gasUsed: 132701 (20.30 USD)
amountOut: 1017.47 USD
multihopSwap 1000 dai -> usdc tx.blockNumber: 13837575, gasUsed: 163973 (25.08 USD)
amountOut: 1007.91 USD
sushiSwap 1000 dai -> usdc tx.blockNumber: 13837576, gasUsed: 131748 (20.15 USD)
amountOut: 1004.58 USD
multihopSwap 1000 dai -> eth -> usdc tx.blockNumber: 13837577, gasUsed: 205664 (31.46 USD)
amountOut: 993.88 USD
sushiSwap 1000 dai -> eth -> usdc VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'
--------------------------------------
singleSwap 10000 dai -> usdc tx.blockNumber: 13837579, gasUsed: 162587 (24.87 USD)
amountOut: 9987.48 USD
multihopSwap 10000 dai -> usdc tx.blockNumber: 13837580, gasUsed: 620482 (94.90 USD)
amountOut: 1962.83 USD
sushiSwap 10000 dai -> usdc VM Exception while processing transaction: reverted with reason string 'SPL'
multihopSwap 10000 dai -> eth -> usdc VM Exception while processing transaction: reverted with reason string 'STF'
sushiSwap 10000 dai -> eth -> usdc VM Exception while processing transaction: reverted with reason string 'TransferHelper: TRANSFER_FROM_FAILED'

```

Run tests:

```bash
npx hardhat test
```

## Disclaimer

Neither does VolumeFi nor Sommelier manage any portfolios. You must make an independent judgment as to whether to add liquidity to portfolios.
Users of this repo should familiarize themselves with smart contracts to further consider the risks associated with smart contracts before adding liquidity to any portfolios or deployed smart contract. These smart contracts are non-custodial and come with no warranties. VolumeFi does not endorse any pools in any of the smart contracts found in this repo. VolumeFi and Sommelier are not giving you investment advice with this software and neither firm has control of your funds. All our smart contract software is alpha, works in progress and are undergoing daily updates that may result in errors or other issues.
