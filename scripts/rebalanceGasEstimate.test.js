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

// addresses of smart contracts in the mainnet
const routerAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564"; // Uniswap V3 SwapRouter
const sushiSwapRouterAddress = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F" // SushiSwap V2 Router
const lendingPoolAddress = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9"; // Aave LendingPool
const incentivesControllerAddress =
  "0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5"; // StakedTokenIncentivesController
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

const Num = (number, decimals) => {
  const [characteristic, mantissa] = number.toString().split(".");
  const padding = mantissa ? decimals - mantissa.length : decimals;
  return characteristic + (mantissa ?? "") + "0".repeat(padding);
};

async function main() {
  const blockNumber = await ethers.provider.getBlockNumber();
  console.log("The latest block number is " + blockNumber);

  gasPrice = await ethers.provider.getGasPrice();
  console.log("gasPrice: " + gasPrice);

  [owner, alice] = await ethers.getSigners();

  console.log(
    "Owner ETH balance: " + (await ethers.provider.getBalance(owner.address))
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

  // uniswap v3 router contract
  swapRouter = await ethers.getContractAt("ISwapRouter", routerAddress);

  await swapRouter.exactOutputSingle(
    [
      wethAddress, // tokenIn
      USDC.address, // tokenOut
      3000, // fee
      owner.address, // recipient
      1647479474, // deadline
      Num(100000, 6), // amountOut
      ethers.utils.parseEther("900"), // amountInMaximum
      0, // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
    ],
    { value: ethers.utils.parseEther("900") }
  );

  console.log("Owner USDC balance: " + (await USDC.balanceOf(owner.address)));

  await swapRouter.connect(alice).exactOutputSingle(
    [
      wethAddress, // tokenIn
      USDC.address, // tokenOut
      3000, // fee
      alice.address, // recipient
      1647479474, // deadline
      Num(100000, 6), // amountOut
      ethers.utils.parseEther("900"), // amountInMaximum
      0, // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
    ],
    { value: ethers.utils.parseEther("900") }
  );

  console.log("Owner USDC balance: " + (await USDC.balanceOf(owner.address)));

  // Deploy cellar contract
  const AaveV2StablecoinCellarGasTest = await ethers.getContractFactory(
    "AaveV2StablecoinCellarGasTest"
  );

  cellar = await AaveV2StablecoinCellarGasTest.deploy(
    USDC.address,
    routerAddress,
    sushiSwapRouterAddress,
    lendingPoolAddress,
    incentivesControllerAddress,
    gravityBridgeAddress,
    stkAAVEAddress,
    AAVE.address
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

  await cellar["deposit(uint256,address)"](Num(5000, 6), owner.address);
  await cellar.connect(alice).deposit(Num(5000, 6), alice.address);

  await cellar.enterStrategy();
  await cellar.accrueFees();

  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  console.log("totalAssets:", await cellar.totalAssets());

  console.log("--------------------------------------");

  tx = await cellar.rebalance([USDC.address, DAI.address], 0);
  gasUsedLog("cellar.rebalance", tx);

  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  console.log("totalAssets:", await cellar.totalAssets());

  console.log("--------------------------------------");

  tx = await cellar.rebalance([DAI.address, USDC.address], 0);
  gasUsedLog("cellar.rebalance", tx);

  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  console.log("totalAssets:", await cellar.totalAssets());

  console.log("--------------------------------------");

  tx = await cellar.rebalanceByCurve(DAI.address, 0);
  gasUsedLog("cellar.rebalanceByCurve", tx);

  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  console.log("totalAssets:", await cellar.totalAssets());

  console.log("--------------------------------------");

  tx = await cellar.rebalanceByCurve(USDC.address, 0);
  gasUsedLog("cellar.rebalanceByCurve", tx);

  console.log("aUSDC balance:", await aUSDC.balanceOf(cellar.address));
  console.log("aDAI balance:", await aDAI.balanceOf(cellar.address));
  console.log("totalAssets:", await cellar.totalAssets());

  console.log("--------------------------------------");

  await cellar.rebalanceByCurve(DAI.address, 0);

  console.log("Owner DAI balance: " + (await DAI.balanceOf(owner.address)));
  tx = await cellar.withdraw(Num(10000, 18), owner.address, owner.address);
  gasUsedLog("cellar.withdraw", tx);
  console.log("Owner DAI balance: " + (await DAI.balanceOf(owner.address)));

  console.log("--------------------------------------");

  await cellar["deposit(uint256,address)"](Num(5000, 18), owner.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
