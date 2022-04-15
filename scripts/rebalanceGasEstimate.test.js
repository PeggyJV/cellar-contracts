const hre = require("hardhat");
const ethers = hre.ethers;

let owner;

let USDC;
let USDT;
let DAI;
let AAVE;

let swapRouter;
let cellar;
let chainlinkETHUSDPriceFeed;

let tx;
let checkedBalanceBefore;
let logText;

let gasPrice;
let ethPriceUSD;

let totalAssetsUSD;

let assetAddress;
let assetATokenAddress;

// addresses of smart contracts in the mainnet
const routerAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564"; // Uniswap V3 SwapRouter
const sushiSwapRouterAddress = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F" // SushiSwap V2 Router

const curveRegistryExchangeAddress = "0x8e764bE4288B842791989DB5b8ec067279829809" // Curve Registry Exchange
const curveStableSwap3PoolAddress = "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7" // Curve Stable Swap 3Pool
const curveStableSwapAavePoolAddress = "0xDeBF20617708857ebe4F679508E7b7863a8A8EeE" // Curve Stable Swap Aave Pool

const lendingPoolAddress = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9"; // Aave LendingPool
const incentivesControllerAddress = "0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5"; // StakedTokenIncentivesController
const gravityBridgeAddress = "0x69592e6f9d21989a043646fE8225da2600e5A0f7" // Cosmos Gravity Bridge contract
const stkAAVEAddress = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"; // StakedTokenV2Rev3
const chainlinkETHUSDPriceFeedAddress = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419" // Chainlink: ETH/USD Price Feed

// addresses of tokens in the mainnet
const aaveAddress = "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9";
const usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const usdtAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

const aUSDCAddress = "0xBcca60bB61934080951369a648Fb03DF4F96263C";
const aDAIAddress = "0x028171bCA77440897B824Ca71D1c56caC55b68A3";

const timetravel = async (addTime) => {
  await network.provider.send("evm_increaseTime", [addTime]);
  await network.provider.send("evm_mine");
};

const gasUsedLog = async (text, tx) => {
  //   console.log("tx: " + JSON.stringify(tx, null, 4))

  let block = await ethers.provider.send("eth_getBlockByNumber", [
    ethers.utils.hexValue(tx.blockNumber),
    true,
  ]);

  //   console.log("block: " + JSON.stringify(block, null, 4))

  let gasUsed = parseInt(block.gasUsed, 16);
  let txFeeUSD = (gasUsed * gasPrice * ethPriceUSD / 10**26).toFixed(2);

  console.log(
    text +
      " tx.blockNumber: " +
      tx.blockNumber +
      ", gasUsed: " +
      gasUsed + " (" +
      txFeeUSD + " USD)"
  );
};

const cellarAssetLog = async (cellar) => {
  const Token = await ethers.getContractFactory(
    "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"
  );

  assetAddress = await cellar.asset();
  console.log("asset:", assetAddress, "(" + (await (await Token.attach(assetAddress)).symbol()) + ")");

  assetATokenAddress = await cellar.assetAToken();
  console.log("assetAToken:", assetATokenAddress, "(" + (await (await Token.attach(assetATokenAddress)).symbol()) + ")");
}

const Num = (number, decimals) => {
  const [characteristic, mantissa] = number.toString().split(".");
  const padding = mantissa ? decimals - mantissa.length : decimals;
  return characteristic + (mantissa ?? "") + "0".repeat(padding);
};

async function main() {
  const blockNumber = await ethers.provider.getBlockNumber();
  console.log("The latest block number is", blockNumber);

  gasPrice = await ethers.provider.getGasPrice();
  console.log("gasPrice:", gasPrice);

  [owner, alice] = await ethers.getSigners();

  console.log(
    "Owner ETH balance:", (await ethers.provider.getBalance(owner.address))
  );

  // stablecoins contracts
  const Token = await ethers.getContractFactory(
    "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"
  );
  USDC = await Token.attach(usdcAddress);
  USDT = await Token.attach(usdtAddress);
  DAI = await Token.attach(daiAddress);
  AAVE = await Token.attach(aaveAddress);
  aUSDC = await Token.attach(aUSDCAddress);
  aDAI = await Token.attach(aDAIAddress);

  // interface for chainlink ETH/USD price feed aggregator V3
  chainlinkETHUSDPriceFeed = await ethers.getContractAt("@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol:AggregatorInterface", chainlinkETHUSDPriceFeedAddress);
  ethPriceUSD = await chainlinkETHUSDPriceFeed.latestAnswer();
  console.log("ethPriceUSD: " + ethPriceUSD);

  curveRegistryExchange = await ethers.getContractAt("ICurveSwaps", curveRegistryExchangeAddress);
  lendingPool = await ethers.getContractAt("ILendingPool", lendingPoolAddress);
  curveStableSwap3Pool = await ethers.getContractAt("ICurveStableSwap3Pool", curveStableSwap3PoolAddress);
  curveStableSwapAavePool = await ethers.getContractAt("ICurveStableSwapAavePool", curveStableSwapAavePoolAddress);
  
  // Uniswap v3 router contract
  swapRouter = await ethers.getContractAt("ISwapRouter", routerAddress);

  await swapRouter.exactOutputSingle(
    [
      wethAddress, // tokenIn
      USDC.address, // tokenOut
      3000, // fee
      owner.address, // recipient
      1649979765, // deadline
      Num(100000, 6), // amountOut
      ethers.utils.parseEther("900"), // amountInMaximum
      0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
    ],
    { value: ethers.utils.parseEther("900") }
  );

  console.log("Owner USDC balance:", (await USDC.balanceOf(owner.address)));

  await swapRouter.connect(alice).exactOutputSingle(
    [
      wethAddress, // tokenIn
      USDC.address, // tokenOut
      3000, // fee
      alice.address, // recipient
      1649979765, // deadline
      Num(100000, 6), // amountOut
      ethers.utils.parseEther("900"), // amountInMaximum
      0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
    ],
    { value: ethers.utils.parseEther("900") }
  );

  console.log("Alice USDC balance:", (await USDC.balanceOf(alice.address)));

  await swapRouter.exactOutputSingle(
    [
      wethAddress, // tokenIn
      DAI.address, // tokenOut
      3000, // fee
      owner.address, // recipient
      1649979765, // deadline
      Num(100000, 18), // amountOut
      ethers.utils.parseEther("900"), // amountInMaximum
      0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
    ],
    { value: ethers.utils.parseEther("900") }
  );

  console.log("Owner DAI balance:", (await DAI.balanceOf(owner.address)));

  await swapRouter.connect(alice).exactOutputSingle(
    [
      wethAddress, // tokenIn
      DAI.address, // tokenOut
      3000, // fee
      alice.address, // recipient
      1649979765, // deadline
      Num(100000, 18), // amountOut
      ethers.utils.parseEther("900"), // amountInMaximum
      0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
    ],
    { value: ethers.utils.parseEther("900") }
  );

  console.log("Alice DAI balance:", (await DAI.balanceOf(alice.address)));

  console.log("------------------- Test swapRouter.exactInputSingle DAI->USDC -------------------");

  await DAI.approve(
    swapRouter.address,
    ethers.constants.MaxUint256
  );

  // Test Uniswap v3 function exactInputSingle 
  tx = await swapRouter.exactInputSingle(
    [
      DAI.address, // tokenIn
      USDC.address, // tokenOut
      3000, // fee
      owner.address, // recipient
      1649979765, // deadline
      Num(1100, 18), // amountIn
      Num(1000, 6), // amountOutMinimum
      0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
    ]
  );
  gasUsedLog("swapRouter.exactInputSingle DAI->USDC", tx);
  console.log("Owner DAI balance:", (await DAI.balanceOf(owner.address)));
  console.log("owner USDC balance:", await USDC.balanceOf(owner.address));

  console.log("------------------- Test swapRouter.exactInput DAI->USDC -------------------");

  // Test Uniswap v3 function exactInput 
  tx = await swapRouter.exactInput(
    [
      ("0x" + DAI.address.slice(2) + '0001f4' + USDC.address.slice(2)).toLowerCase(), // path
      owner.address, // recipient
      1649979765, // deadline
      Num(1100, 18), // amountIn
      Num(1000, 6) // amountOutMinimum
    ]
  );
  gasUsedLog("swapRouter.exactInput DAI->USDC", tx);
  console.log("Owner DAI balance:", (await DAI.balanceOf(owner.address)));
  console.log("owner USDC balance:", await USDC.balanceOf(owner.address));

  console.log("------------------- Test curveStableSwap3Pool.exchange DAI->USDC -------------------");

  await DAI.approve(
    curveStableSwap3Pool.address,
    ethers.constants.MaxUint256
  );

  // Test Curve Stable Swap 3Pool function exchange
  tx = await curveStableSwap3Pool.exchange(
    0,
    1,
    Num(1000, 18),
    0
  )
  gasUsedLog("curveStableSwap3Pool.exchange DAI->USDC", tx);

  console.log("owner DAI balance:", await DAI.balanceOf(owner.address));
  console.log("owner USDC balance:", await USDC.balanceOf(owner.address));

  console.log("------------------- Test curveStableSwapAavePool.exchange aDAI->aUSDC -------------------");

  DAI.approve(
    lendingPool.address,
    ethers.constants.MaxUint256
  );

  // Deposit DAI to Aave protocol
  tx = await lendingPool.deposit(DAI.address, Num(1000, 18), owner.address, 0);
  gasUsedLog("lendingPool.deposit", tx);

  console.log("owner aDAI balance:", await aDAI.balanceOf(owner.address));
  console.log("owner aUSDC balance:", await aUSDC.balanceOf(owner.address));
  
  await aDAI.approve(
    curveStableSwapAavePool.address,
    ethers.constants.MaxUint256
  );

  // Test Curve Stable Swap Aave Pool function exchange
  tx = await curveStableSwapAavePool.exchange(
    0,
    1,
    Num(1000, 18),
    0
  )
  gasUsedLog("curveStableSwapAavePool.exchange aDAI->aUSDC", tx);

  console.log("owner aDAI balance:", await aDAI.balanceOf(owner.address));
  console.log("owner aUSDC balance:", await aUSDC.balanceOf(owner.address));

  console.log("------------------- Test curveRegistryExchange.exchange_multiple DAI->USDC -------------------");

  await DAI.approve(
    curveRegistryExchange.address,
    ethers.constants.MaxUint256
  );

  // Test Curve Registry Exchange function exchange_multiple
  tx = await curveRegistryExchange["exchange_multiple(address[9],uint256[3][4],uint256,uint256)"](
    [
      DAI.address,
      curveStableSwap3PoolAddress,
      USDC.address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000"
    ],
    [
      [0, 1, 1], // [i, j, swap type], where i and j: 0 - DAI, 1 - USDC, 2 - USDT; swap type: 1 - for a stableswap `exchange`
      [0, 0, 0],
      [0, 0, 0],
      [0, 0, 0]
    ],
    Num(1000, 18),
    Num(995, 6)
  )
  gasUsedLog("curveRegistryExchange.exchange_multiple DAI->USDC", tx);

  console.log("owner DAI balance:", await DAI.balanceOf(owner.address));
  console.log("owner USDC balance:", await USDC.balanceOf(owner.address));

  console.log("------------------- Test curveRegistryExchange.exchange_multiple aDAI->aUSDC -------------------");

  // Deposit DAI to Aave protocol
  tx = await lendingPool.deposit(DAI.address, Num(1000, 18), owner.address, 0);
  gasUsedLog("lendingPool.deposit", tx);

  console.log("owner aDAI balance:", await aDAI.balanceOf(owner.address));
  console.log("owner aUSDC balance:", await aUSDC.balanceOf(owner.address));

  await aDAI.approve(
    curveRegistryExchange.address,
    ethers.constants.MaxUint256
  );

  // Test Curve Registry Exchange function exchange_multiple
  tx = await curveRegistryExchange["exchange_multiple(address[9],uint256[3][4],uint256,uint256)"](
    [
      aDAI.address,
      curveStableSwapAavePoolAddress,
      aUSDC.address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000"
    ],
    [
      [0, 1, 1], // [i, j, swap type], where i and j: 0 - aDAI, 1 - aUSDC, 2 - aUSDT; swap type: 1 - for a stableswap `exchange`
      [0, 0, 0],
      [0, 0, 0],
      [0, 0, 0]
    ],
    Num(1000, 18),
    Num(995, 6)
  )
  gasUsedLog("curveRegistryExchange.exchange_multiple aDAI->aUSDC", tx);

  console.log("owner aDAI balance:", await aDAI.balanceOf(owner.address));
  console.log("owner aUSDC balance:", await aUSDC.balanceOf(owner.address));

  console.log("--------------------------------------");

  // Deploy cellar contract
  const AaveV2StablecoinCellar = await ethers.getContractFactory(
    "AaveV2StablecoinCellar"
  );

  cellar = await AaveV2StablecoinCellar.deploy(
    USDC.address,
    curveRegistryExchangeAddress,
    sushiSwapRouterAddress,
    lendingPoolAddress,
    incentivesControllerAddress,
    gravityBridgeAddress,
    stkAAVEAddress,
    AAVE.address,
    wethAddress
  );
  await cellar.deployed();

  await USDC.approve(
    cellar.address,
    ethers.constants.MaxUint256
  );

  await USDC.connect(alice).approve(
    cellar.address,
    ethers.constants.MaxUint256
  );

  await DAI.approve(
    cellar.address,
    ethers.constants.MaxUint256
  );

  await DAI.connect(alice).approve(
    cellar.address,
    ethers.constants.MaxUint256
  );

  console.log("deposit to cellar 10000$");
  await cellar["deposit(uint256,address)"](Num(5000, (await cellar.assetDecimals())), owner.address);
  await cellar.connect(alice).deposit(Num(5000, (await cellar.assetDecimals())), alice.address);

  tx = await cellar.enterStrategy();
  gasUsedLog("cellar.enterStrategy", tx);
  await cellar.accrueFees();

  console.log("------------------- Test cellar.rebalance USDC->DAI -------------------");
  
  console.log("deposit to cellar 2000$");
  await cellar["deposit(uint256,address)"](Num(1000, (await cellar.assetDecimals())), owner.address);
  await cellar.connect(alice).deposit(Num(1000, (await cellar.assetDecimals())), alice.address);

  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));

  totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
  console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");
  console.log("asset:", await cellar.asset() + (await ((await Token.attach(await cellar.asset()))).symbol()));
  console.log("assetAToken:", await cellar.assetAToken());
  

  tx = await cellar["rebalance(address[9],uint256[3][4],uint256,bool)"](
    [
      USDC.address,
      curveStableSwap3Pool.address,
      DAI.address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000"
    ],
    [
      [1, 0, 1], // [i, j, swap type], where i and j: 0 - DAI, 1 - USDC, 2 - USDT; swap type: 1 - for a stableswap `exchange`
      [0, 0, 0],
      [0, 0, 0],
      [0, 0, 0]
    ],
    0,
    false
  );
  gasUsedLog("cellar.rebalance USDC->DAI", tx);

  await cellarAssetLog(cellar);
  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
  console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");

  console.log("------------------- Test cellar.rebalance DAI->USDC -------------------");
  
  console.log("deposit to cellar 2000$");
  await cellar["deposit(uint256,address)"](Num(1000, (await cellar.assetDecimals())), owner.address);
  await cellar.connect(alice).deposit(Num(1000, (await cellar.assetDecimals())), alice.address);

  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
  console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

  tx = await cellar["rebalance(address[9],uint256[3][4],uint256,bool)"](
    [
      DAI.address,
      curveStableSwap3Pool.address,
      USDC.address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000"
    ],
    [
      [0, 1, 1], // [i, j, swap type], where i and j: 0 - DAI, 1 - USDC, 2 - USDT; swap type: 1 - for a stableswap `exchange`
      [0, 0, 0],
      [0, 0, 0],
      [0, 0, 0]
    ],
    0,
    false
  );
  gasUsedLog("cellar.rebalance DAI->USDC", tx);

  await cellarAssetLog(cellar);
  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
  console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");

  console.log("------------------- Test cellar.rebalance aUSDC->aDAI -------------------");
  
  console.log("deposit to cellar 2000$");
  await cellar["deposit(uint256,address)"](Num(1000, (await cellar.assetDecimals())), owner.address);
  await cellar.connect(alice).deposit(Num(1000, (await cellar.assetDecimals())), alice.address);

  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
  console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

  tx = await cellar["rebalance(address[9],uint256[3][4],uint256,bool)"](
    [
      aUSDC.address,
      curveStableSwapAavePool.address,
      aDAI.address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000"
    ],
    [
      [1, 0, 1], // [i, j, swap type], where i and j: 0 - aDAI, 1 - aUSDC, 2 - aUSDT; swap type: 1 - for a stableswap `exchange`
      [0, 0, 0],
      [0, 0, 0],
      [0, 0, 0]
    ],
    0,
    true
  );
  gasUsedLog("cellar.rebalance aUSDC->aDAI", tx);

  await cellarAssetLog(cellar);
  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
  console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");

  console.log("------------------- Test cellar.rebalance aDAI->aUSDC -------------------");

  console.log("deposit to cellar 2000$");
  await cellar["deposit(uint256,address)"](Num(1000, (await cellar.assetDecimals())), owner.address);
  await cellar.connect(alice).deposit(Num(1000, (await cellar.assetDecimals())), alice.address);

  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
  console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

  tx = await cellar["rebalance(address[9],uint256[3][4],uint256,bool)"](
    [
      aDAI.address,
      curveStableSwapAavePool.address,
      aUSDC.address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
    ],
    [
      [0, 1, 1], // [i, j, swap type], where i and j: 0 - aDAI, 1 - aUSDC, 2 - aUSDT; swap type: 1 - for a stableswap `exchange`
      [0, 0, 0],
      [0, 0, 0],
      [0, 0, 0]
    ],
    0,
    true
  );
  gasUsedLog("cellar.rebalance aDAI->aUSDC", tx);

  await cellarAssetLog(cellar);
  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
  console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");

  console.log("--------------------------------------");

  await cellar["deposit(uint256,address)"](Num(100, (await cellar.assetDecimals())), owner.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
