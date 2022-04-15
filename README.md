# cellar-contracts

Cellar contracts for Sommelier Network

## Testing

Run tests:

```bash
yarn test
```

Run scripts:

```bash
npx hardhat --network hardhat run scripts/rebalanceGasEstimate.test.js

The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: BigNumber { value: "10000000000000000000000" }
ethPriceUSD: 280554287181
Owner USDC balance: BigNumber { value: "100000000000" }
Alice USDC balance: BigNumber { value: "100000000000" }
Owner DAI balance: BigNumber { value: "100000000000000000000000" }
Alice DAI balance: BigNumber { value: "100000000000000000000000" }
------------------- Test swapRouter.exactInputSingle DAI->USDC -------------------
swapRouter.exactInputSingle DAI->USDC tx.blockNumber: 14316390, gasUsed: 186031 (29.50 USD)
Owner DAI balance: BigNumber { value: "98900000000000000000000" }
owner USDC balance: BigNumber { value: "101093900449" }
------------------- Test swapRouter.exactInput DAI->USDC -------------------
swapRouter.exactInput DAI->USDC tx.blockNumber: 14316391, gasUsed: 115983 (18.39 USD)
Owner DAI balance: BigNumber { value: "97800000000000000000000" }
owner USDC balance: BigNumber { value: "102193075139" }
------------------- Test curveStableSwap3Pool.exchange DAI->USDC -------------------
curveStableSwap3Pool.exchange DAI->USDC tx.blockNumber: 14316393, gasUsed: 127775 (20.26 USD)
owner DAI balance: BigNumber { value: "96800000000000000000000" }
owner USDC balance: BigNumber { value: "103192797445" }
------------------- Test curveStableSwapAavePool.exchange aDAI->aUSDC -------------------
lendingPool.deposit tx.blockNumber: 14316395, gasUsed: 283152 (44.90 USD)
owner aDAI balance: BigNumber { value: "1000000000000000000000" }
owner aUSDC balance: BigNumber { value: "0" }
curveStableSwapAavePool.exchange aDAI->aUSDC tx.blockNumber: 14316397, gasUsed: 473855 (75.14 USD)
owner aDAI balance: BigNumber { value: "1389081786028" }
owner aUSDC balance: BigNumber { value: "999523264" }
------------------- Test curveRegistryExchange.exchange_multiple DAI->USDC -------------------
curveRegistryExchange.exchange_multiple DAI->USDC tx.blockNumber: 14316399, gasUsed: 207784 (32.95 USD)
owner DAI balance: BigNumber { value: "94800000000000000000000" }
owner USDC balance: BigNumber { value: "104192519751" }
------------------- Test curveRegistryExchange.exchange_multiple aDAI->aUSDC -------------------
lendingPool.deposit tx.blockNumber: 14316400, gasUsed: 231842 (36.76 USD)
owner aDAI balance: BigNumber { value: "1000000001389081789887" }
owner aUSDC balance: BigNumber { value: "999523266" }
curveRegistryExchange.exchange_multiple aDAI->aUSDC tx.blockNumber: 14316402, gasUsed: 636170 (100.88 USD)
owner aDAI balance: BigNumber { value: "2778160091924" }
owner aUSDC balance: BigNumber { value: "1999046461" }
--------------------------------------
deposit to cellar 10000$
cellar.enterStrategy tx.blockNumber: 14316410, gasUsed: 334102 (52.98 USD)
------------------- Test cellar.rebalance USDC->DAI -------------------
deposit to cellar 2000$
aUSDC balance: BigNumber { value: "10000000015" }
aDAI balance: BigNumber { value: "0" }
totalAssets: 12000.00$
asset: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48USDC
assetAToken: 0xBcca60bB61934080951369a648Fb03DF4F96263C
cellar.rebalance USDC->DAI tx.blockNumber: 14316414, gasUsed: 756815 (120.01 USD)
asset: 0x6B175474E89094C44Da98b954EedeAC495271d0F (DAI)
assetAToken: 0x028171bCA77440897B824Ca71D1c56caC55b68A3 (aDAI)
aUSDC balance: BigNumber { value: "0" }
aDAI balance: BigNumber { value: "11996132330410569241804" }
totalAssets: 11996.13$
Difference totalAssets: -3.87$
------------------- Test cellar.rebalance DAI->USDC -------------------
deposit to cellar 2000$
aUSDC balance: BigNumber { value: "0" }
aDAI balance: BigNumber { value: "11996132363736698858746" }
totalAssets: 13996.13$
cellar.rebalance DAI->USDC tx.blockNumber: 14316417, gasUsed: 663291 (105.18 USD)
asset: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC)
assetAToken: 0xBcca60bB61934080951369a648Fb03DF4F96263C (aUSDC)
aUSDC balance: BigNumber { value: "13992245754" }
aDAI balance: BigNumber { value: "0" }
totalAssets: 13992.25$
Difference totalAssets: -3.89$
------------------- Test cellar.rebalance aUSDC->aDAI -------------------
deposit to cellar 2000$
aUSDC balance: BigNumber { value: "13992245790" }
aDAI balance: BigNumber { value: "0" }
totalAssets: 15992.25$
cellar.rebalance aUSDC->aDAI tx.blockNumber: 14316420, gasUsed: 862638 (136.79 USD)
asset: 0x6B175474E89094C44Da98b954EedeAC495271d0F (DAI)
assetAToken: 0x028171bCA77440897B824Ca71D1c56caC55b68A3 (aDAI)
aUSDC balance: BigNumber { value: "0" }
aDAI balance: BigNumber { value: "15987028738976040347158" }
totalAssets: 15987.03$
Difference totalAssets: -5.22$
------------------- Test cellar.rebalance aDAI->aUSDC -------------------
deposit to cellar 2000$
aUSDC balance: BigNumber { value: "0" }
aDAI balance: BigNumber { value: "15987028794494127757482" }
totalAssets: 17987.03$
cellar.rebalance aDAI->aUSDC tx.blockNumber: 14316423, gasUsed: 811798 (128.72 USD)
asset: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC)
assetAToken: 0xBcca60bB61934080951369a648Fb03DF4F96263C (aUSDC)
aUSDC balance: BigNumber { value: "17978460591" }
aDAI balance: BigNumber { value: "0" }
totalAssets: 17978.46$
Difference totalAssets: -8.57$
--------------------------------------


```
