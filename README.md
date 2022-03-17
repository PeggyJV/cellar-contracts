# Sommelier Aave Stablecoin Cellar
AaveStablecoinCellar contract for Sommelier Network

## Testing and Development on testnet

### Dependencies
* [nodejs](https://nodejs.org/en/download/) - >=v8, tested with version v14.15.4
* hardhat

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

Run tests:

```bash
npx hardhat test
```

## Disclaimer
Neither does VolumeFi nor Sommelier manage any portfolios. You must make an independent judgment as to whether to add liquidity to portfolios.
Users of this repo should familiarize themselves with smart contracts to further consider the risks associated with smart contracts before adding liquidity to any portfolios or deployed smart contract. These smart contracts are non-custodial and come with no warranties. VolumeFi does not endorse any pools in any of the smart contracts found in this repo. VolumeFi and Sommelier are not giving you investment advice with this software and neither firm has control of your funds. All our smart contract software is alpha, works in progress and are undergoing daily updates that may result in errors or other issues.
