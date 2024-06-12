### Using Cellars

A Cellar is a contract that holds and deploys funds in DeFi as managed by a strategist.

A Strategist begins by deploying a Cellar contract. The Base cellars contract is located here `src/base/Cellar.sol`. Typiccally a strategists will choose to deploy one of the permutations of the base cellar contract located in `src/base/permutations`


### Deploying Cellars

Examples of past production deployments of Cellars can be found in the `scripts` directory.

Below we are going to go through a mock deployment of a cellars.

1. First we configure the core set of variables.

The `devOwner` is the intitial owner of the Cellar contract. The ownership will be transferred to the Sommelier gravity contract instance after the Cellar is fully configured. The stratgists should have control of this address.

The `deployer` is the instance of the deployer contract that will be used to deploy the Cellar. This is an optional process that uses a deployer contract to get determinsistic addresses for the Cellars.

The `registry` is the instance of the registry contract that will be used to register adapaters for the Cellar. The registry is a contract that holds the addresses of all the adapters that the Cellar will use and is typically managed by a timelock multisig. We will go into more detail about how to configure the registry in another section.

The `priceRouter` is the instance of the PriceRouter contract that will be used to get prices assets for the Cellar. The priceRouter is a contract that interfaces with multiple price oracles to get the price of assets.



``` solidity
address public devOwner = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;

Deployer public deployer = Deployer(deployerAddress);

Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);

PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

```

Pick a permutation of the cellar for your contract. `CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport` is the state of the art cellar that supports some advanced capabilities.

These capabilities include

1. Balancer Flash Loans for leveraged staking.
2. A erc4626 Price Oracle for pricing the shares. These oracles allow amoritizing the costs of pricing assets in the cellar through an oracle so that deposits and withdrawals can be quite a bit cheaper than using the price router to price shares on every deposit and withdrawal.
3. MultiAssetDeposit allows the cellar to accept multiple assets as deposit addresses. The base cellar architecture only supported a single deposit address.
4. NativeSupport allows the cellar to support eth transfers for deposits without requiring the user to wrap their eth in weth.


``` solidity

CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public cellar;
```

2. More cellar specific important variables

``` solidity

string memory cellarName,
string memory cellarSymbol,
ERC20 holdingAsset,
uint32 holdingPosition,
bytes memory holdingPositionConfig,
uint256 initialDeposit,
uint64 platformCut
```
