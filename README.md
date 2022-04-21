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
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 100000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestByBalancer2 -------------------
totalAssets: 100448.75$
cellar.reinvestByBalancer2 tx.blockNumber: 14316398, gasUsed: 1042556 (165.31 USD)
totalAssets: 100521.97$
Difference totalAssets: 73.23$
      ✓ cellar.reinvestByBalancer2 USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 100000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestByBalancer -------------------
totalAssets: 100448.75$
cellar.reinvestByBalancer tx.blockNumber: 14316398, gasUsed: 982142 (155.74 USD)
totalAssets: 100521.97$
Difference totalAssets: 73.23$
      ✓ cellar.reinvestByBalancer USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 100000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 100448.75$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 844367 (133.89 USD)
totalAssets: 100520.75$
Difference totalAssets: 72.01$
      ✓ cellar.reinvest USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 100000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 100448.75$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 973908 (154.43 USD)
totalAssets: 100521.06$
Difference totalAssets: 72.32$
      ✓ cellar.reinvestHybrid USDC
    Strategy with 1_000_000 USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 1000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestByBalancer2 -------------------
totalAssets: 1004484.05$
cellar.reinvestByBalancer2 tx.blockNumber: 14316398, gasUsed: 1042556 (165.31 USD)
totalAssets: 1005212.45$
Difference totalAssets: 728.40$
      ✓ cellar.reinvestByBalancer2 USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 1000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestByBalancer -------------------
totalAssets: 1004484.05$
cellar.reinvestByBalancer tx.blockNumber: 14316398, gasUsed: 982142 (155.74 USD)
totalAssets: 1005212.46$
Difference totalAssets: 728.40$
      ✓ cellar.reinvestByBalancer USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 1000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 1004484.05$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 844367 (133.89 USD)
totalAssets: 1005203.78$
Difference totalAssets: 719.73$
      ✓ cellar.reinvest USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 1000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 1004484.05$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 973908 (154.43 USD)
totalAssets: 1005206.92$
Difference totalAssets: 722.87$
      ✓ cellar.reinvestHybrid USDC
    Strategy with 8_000_000 USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestByBalancer2 -------------------
totalAssets: 8035660.60$
cellar.reinvestByBalancer2 tx.blockNumber: 14316398, gasUsed: 1042556 (165.31 USD)
totalAssets: 8041258.26$
Difference totalAssets: 5597.66$
      ✓ cellar.reinvestByBalancer2 USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestByBalancer -------------------
totalAssets: 8035660.60$
cellar.reinvestByBalancer tx.blockNumber: 14316398, gasUsed: 982142 (155.74 USD)
totalAssets: 8041258.26$
Difference totalAssets: 5597.67$
      ✓ cellar.reinvestByBalancer USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 8035660.59$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 844367 (133.89 USD)
totalAssets: 8041397.99$
Difference totalAssets: 5737.40$
      ✓ cellar.reinvest USDC
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 8035660.59$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 973908 (154.43 USD)
totalAssets: 8041425.33$
Difference totalAssets: 5764.74$
      ✓ cellar.reinvestHybrid USDC
    Strategy with 8_000_000 DAI
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestByBalancer2 -------------------
totalAssets: 8045866.29$

      1) cellar.reinvestByBalancer2 DAI
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 8045866.29$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 803050 (127.34 USD)
totalAssets: 8053472.88$
Difference totalAssets: 7606.59$
      ✓ cellar.reinvest DAI
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 8045866.28$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 932591 (147.88 USD)
totalAssets: 8053510.23$
Difference totalAssets: 7643.94$
      ✓ cellar.reinvestHybrid DAI
    Strategy with 8_000_000 USDT
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestByBalancer2 -------------------
totalAssets: 8064596.61$

      2) cellar.reinvestByBalancer2 USDT
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvest -------------------
totalAssets: 8064596.62$
cellar.reinvest tx.blockNumber: 14316398, gasUsed: 819949 (130.02 USD)
totalAssets: 8069113.07$
Difference totalAssets: 4516.45$
      ✓ cellar.reinvest USDT
The latest block number is 14316384
gasPrice: BigNumber { value: "56519151995" }
Owner ETH balance: 1000000
ethPriceUSD: 280554287181
Owner USDC balance: 10000000
Alice USDC balance: 10000000
cellar.removeLiquidityRestriction
deposit to cellar 8000000$
timetravel 3 month
cellar.claimAndUnstake tx.blockNumber: 14316396, gasUsed: 458284 (72.67 USD)
timetravel 10 day
------------------- Test cellar.reinvestHybrid -------------------
totalAssets: 8064596.61$
cellar.reinvestHybrid tx.blockNumber: 14316398, gasUsed: 949490 (150.56 USD)
totalAssets: 8069134.13$
Difference totalAssets: 4537.53$
      ✓ cellar.reinvestHybrid USDT

·--------------------------------------------------------------------------------------|---------------------------|-------------|-----------------------------·
|                                 Solc version: 0.8.11                                 ·  Optimizer enabled: true  ·  Runs: 100  ·  Block limit: 30000000 gas  │
·······················································································|···························|·············|······························
|  Methods                                                                             ·               52 gwei/gas               ·       3055.44 usd/eth       │
························································|······························|·············|·············|·············|···············|··············
|  Contract                                             ·  Method                      ·  Min        ·  Max        ·  Avg        ·  # calls      ·  usd (avg)  │
························································|······························|·············|·············|·············|···············|··············
|  @openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20  ·  approve                     ·          -  ·          -  ·      60311  ·           36  ·       9.58  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  accrueFees                  ·     172194  ·     182425  ·     180046  ·           18  ·      28.61  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  claimAndUnstake             ·          -  ·          -  ·     458284  ·           18  ·      72.81  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  deposit                     ·     177180  ·     180910  ·     179046  ·           36  ·      28.45  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  enterStrategy               ·          -  ·          -  ·     334125  ·           12  ·      53.09  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  rebalance                   ·     571469  ·     593034  ·     582252  ·            6  ·      92.51  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  reinvest                    ·     803050  ·     844367  ·     831220  ·            5  ·     132.07  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  reinvestByBalancer          ·          -  ·          -  ·     982142  ·            3  ·     156.05  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  reinvestByBalancer2         ·          -  ·          -  ·    1042556  ·            3  ·     165.64  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  reinvestHybrid              ·     932591  ·     973908  ·     960761  ·            5  ·     152.65  │
························································|······························|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                               ·  removeLiquidityRestriction  ·          -  ·          -  ·      29216  ·           18  ·       4.64  │
························································|······························|·············|·············|·············|···············|··············
|  Deployments                                                                         ·                                         ·  % of limit   ·             │
·······················································································|·············|·············|·············|···············|··············
|  AaveV2StablecoinCellar                                                              ·          -  ·          -  ·    5380064  ·       17.9 %  ·     854.80  │
·--------------------------------------------------------------------------------------|-------------|-------------|-------------|---------------|-------------·

  16 passing (6m)
  2 failing

  1) reinvest gas and profit estimate
       Strategy with 8_000_000 DAI
         cellar.reinvestByBalancer2 DAI:
     Error: VM Exception while processing transaction: reverted with reason string 'ERR_MAX_IN_RATIO'
      at <UnrecognizedContract>.<unknown> (0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a)
      at <UnrecognizedContract>.<unknown> (0x3e66b66fd1d0b02fda6c811da9e0547970db2f21)
      at AaveV2StablecoinCellar.reinvestByBalancer2 (contracts/AaveV2StablecoinCellar.sol:1001)
      at async HardhatNode._mineBlockWithPendingTxs (node_modules/hardhat/src/internal/hardhat-network/provider/node.ts:1724:23)
      at async HardhatNode.mineBlock (node_modules/hardhat/src/internal/hardhat-network/provider/node.ts:458:16)
      at async EthModule._sendTransactionAndReturnHash (node_modules/hardhat/src/internal/hardhat-network/provider/modules/eth.ts:1496:18)
      at async HardhatNetworkProvider.request (node_modules/hardhat/src/internal/hardhat-network/provider/provider.ts:118:18)
      at async EthersProviderWrapper.send (node_modules/@nomiclabs/hardhat-ethers/src/internal/ethers-provider-wrapper.ts:13:20)

  2) reinvest gas and profit estimate
       Strategy with 8_000_000 USDT
         cellar.reinvestByBalancer2 USDT:
     Error: Transaction reverted without a reason string
      at <UnrecognizedContract>.<unknown> (0x3e66b66fd1d0b02fda6c811da9e0547970db2f21)
      at AaveV2StablecoinCellar.reinvestByBalancer2 (contracts/AaveV2StablecoinCellar.sol:994)
      at async HardhatNode._mineBlockWithPendingTxs (node_modules/hardhat/src/internal/hardhat-network/provider/node.ts:1724:23)
      at async HardhatNode.mineBlock (node_modules/hardhat/src/internal/hardhat-network/provider/node.ts:458:16)
      at async EthModule._sendTransactionAndReturnHash (node_modules/hardhat/src/internal/hardhat-network/provider/modules/eth.ts:1496:18)
      at async HardhatNetworkProvider.request (node_modules/hardhat/src/internal/hardhat-network/provider/provider.ts:118:18)
      at async EthersProviderWrapper.send (node_modules/@nomiclabs/hardhat-ethers/src/internal/ethers-provider-wrapper.ts:13:20)


```




