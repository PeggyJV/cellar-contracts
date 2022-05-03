# cellar-contracts

Cellar contracts for Sommelier Network

## Testing

Run tests:

```bash
yarn test
```

```bash
npx hardhat test --grep 'reinvest gas and profit estimate'

  reinvest gas and profit estimate
    Strategy with 100_000 USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 100000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 100448.75$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 844330 (133.88 USD)
totalAssets: 100520.75$
Difference totalAssets: 72.01$
      ✓ cellar.reinvest USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 100000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 100448.75$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 973852 (154.42 USD)
totalAssets: 100521.06$
Difference totalAssets: 72.32$
      ✓ cellar.reinvestHybrid USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 100000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------
totalAssets: 100448.75$
cellar.reinvestBalancerProxyAndBalancerVault tx.blockNumber: 14316398, gasUsed: 982347 (155.77 USD)
totalAssets: 100521.41$
Difference totalAssets: 72.66$
      ✓ cellar.reinvestBalancerProxyAndBalancerVault USDC
    Strategy with 1_000_000 USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 1000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 1004484.05$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 844330 (133.88 USD)
totalAssets: 1005203.78$
Difference totalAssets: 719.73$
      ✓ cellar.reinvest USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 1000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 1004484.05$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 973852 (154.42 USD)
totalAssets: 1005206.92$
Difference totalAssets: 722.87$
      ✓ cellar.reinvestHybrid USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 1000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------
totalAssets: 1004484.05$
cellar.reinvestBalancerProxyAndBalancerVault tx.blockNumber: 14316398, gasUsed: 982347 (155.77 USD)
totalAssets: 1005210.24$
Difference totalAssets: 726.19$
      ✓ cellar.reinvestBalancerProxyAndBalancerVault USDC
    Strategy with 8_000_000 USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 8035660.59$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 844330 (133.88 USD)
totalAssets: 8041397.99$
Difference totalAssets: 5737.41$
      ✓ cellar.reinvest USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 8035660.59$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 973852 (154.42 USD)
totalAssets: 8041425.33$
Difference totalAssets: 5764.74$
      ✓ cellar.reinvestHybrid USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------
totalAssets: 8035660.59$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 982347 (155.77 USD)
totalAssets: 8041442.20$
Difference totalAssets: 5781.61$
      ✓ cellar.reinvestBalancerProxyAndBalancerVault USDC
    Strategy with 8_000_000 DAI
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 8045866.28$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 803013 (127.33 USD)
totalAssets: 8053472.88$
Difference totalAssets: 7606.60$
      ✓ cellar.reinvest DAI
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 8045866.28$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 932535 (147.87 USD)
totalAssets: 8053510.23$
Difference totalAssets: 7643.95$
      ✓ cellar.reinvestHybrid DAI
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------
totalAssets: 8045866.28$
cellar.reinvestBalancerProxyAndBalancerVault tx.blockNumber: 14316398, gasUsed: 941685 (149.32 USD)
totalAssets: 8053508.01$
Difference totalAssets: 7641.74$
      ✓ cellar.reinvestBalancerProxyAndBalancerVault DAI
    Strategy with 8_000_000 USDT
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 8064596.60$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 819912 (130.01 USD)
totalAssets: 8069113.05$
Difference totalAssets: 4516.45$
      ✓ cellar.reinvest USDT
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 8064596.60$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 949434 (150.55 USD)
totalAssets: 8069134.12$
Difference totalAssets: 4537.53$
      ✓ cellar.reinvestHybrid USDT
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000001
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458306 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------
totalAssets: 8064596.60$
cellar.reinvestBalancerProxyAndBalancerVault tx.blockNumber: 14316398, gasUsed: 942356 (149.43 USD)
totalAssets: 8069082.22$
Difference totalAssets: 4485.62$
      ✓ cellar.reinvestBalancerProxyAndBalancerVault USDT

·-------------------------------------------------------------------------------------------------|---------------------------|-------------|-----------------------------·
|                                      Solc version: 0.8.11                                       ·  Optimizer enabled: true  ·  Runs: 100  ·  Block limit: 30000000 gas  │
··································································································|···························|·············|······························
|  Methods                                                                                                                                                                │
························································|·········································|·············|·············|·············|···············|··············
|  Contract                                             ·  Method                                 ·  Min        ·  Max        ·  Avg        ·  # calls      ·  usd (avg)  │
························································|·········································|·············|·············|·············|···············|··············
|  @openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20  ·  approve                                ·          -  ·          -  ·      60311  ·           30  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  accrueFees                             ·     172194  ·     182425  ·     179570  ·           15  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  claimAndUnstake                        ·          -  ·          -  ·     458306  ·           15  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  deposit                                ·     177202  ·     180944  ·     179074  ·           30  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  enterStrategy                          ·          -  ·          -  ·     334147  ·            9  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  rebalance                              ·     571397  ·     592962  ·     582180  ·            6  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  reinvest                               ·     803013  ·     844330  ·     831183  ·            5  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  reinvestBalancerProxyAndBalancerVault  ·     941685  ·     982347  ·     966216  ·            5  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  reinvestHybrid                         ·     932535  ·     973852  ·     960705  ·            5  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  removeLiquidityRestriction             ·          -  ·          -  ·      29238  ·           15  ·          -  │
························································|·········································|·············|·············|·············|···············|··············
|  Deployments                                                                                    ·                                         ·  % of limit   ·             │
··································································································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                                                                         ·          -  ·          -  ·    5315732  ·       17.7 %  ·          -  │
·-------------------------------------------------------------------------------------------------|-------------|-------------|-------------|---------------|-------------·

  15 passing (24s)


```




