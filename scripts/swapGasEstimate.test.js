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

const amountOutLog = async (token) => {
  console.log("amountOut: " + (((await token.balanceOf(cellar.address)) - checkedBalanceBefore)/10**(await token.decimals())).toFixed(2) + " USD");
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

  [owner] = await ethers.getSigners();

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

  // interface for chainlink ETH/USD price feed aggregator V3
  chainlinkETHUSDPriceFeed = await ethers.getContractAt("@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol:AggregatorInterface", chainlinkETHUSDPriceFeedAddress);
  ethPriceUSD = await chainlinkETHUSDPriceFeed.latestAnswer();
  console.log("ethPriceUSD: " + ethPriceUSD);

  // uniswap v3 router contract
  swapRouter = await ethers.getContractAt("ISwapRouter", routerAddress);

  // test swapRouter.exactOutputSingle
  await swapRouter.exactOutputSingle(
    [
      wethAddress, // tokenIn
      USDC.address, // tokenOut
      3000, // fee
      owner.address, // recipient
      1647479474, // deadline
      Num(1000000, 6), // amountOut
      ethers.utils.parseEther("9000"), // amountInMaximum
      0, // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
    ],
    { value: ethers.utils.parseEther("9000") }
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
    Num(900000, 6)
  );

  await cellar["deposit(uint256,address)"](Num(50000, 6), owner.address);

  console.log("--------------------------------------");

  // 50 USDC -> DAI
  logText = "singleSwap 50 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(50, 6),
      1,
      true,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 50 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(50, 6),
      1,
      true,
      true
    );
    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 50 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(50, 6),
      1,
      false,
      false
    );
    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 50 USDC -> WETH -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, wethAddress, DAI.address],
      Num(50, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 50 USDC -> WETH -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, wethAddress, DAI.address],
      Num(50, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 50 USDC -> USDT -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, USDT.address, DAI.address],
      Num(50, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 50 USDC -> USDT -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, USDT.address, DAI.address],
      Num(50, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  console.log("--------------------------------------");

  // 1000 USDC -> DAI
  logText = "singleSwap 1000 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(1000, 6),
      1,
      true,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 1000 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(1000, 6),
      1,
      true,
      true
    );
    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 1000 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(1000, 6),
      1,
      false,
      false
    );
    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 1000 USDC -> WETH -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, wethAddress, DAI.address],
      Num(1000, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 1000 USDC -> WETH -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, wethAddress, DAI.address],
      Num(1000, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 1000 USDC -> USDT -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, USDT.address, DAI.address],
      Num(1000, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 1000 USDC -> USDT -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, USDT.address, DAI.address],
      Num(1000, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  console.log("--------------------------------------");

  // 5000 USDC -> DAI
  logText = "singleSwap 5000 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(5000, 6),
      1,
      true,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 5000 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(5000, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 5000 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(5000, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }


  logText = "multihopSwap 5000 USDC -> WETH -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, wethAddress, DAI.address],
      Num(5000, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 5000 USDC -> WETH -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, wethAddress, DAI.address],
      Num(5000, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 5000 USDC -> USDT -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, USDT.address, DAI.address],
      Num(5000, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 5000 USDC -> USDT -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, USDT.address, DAI.address],
      Num(5000, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  console.log("--------------------------------------");

  // 10000 USDC -> DAI
  logText = "singleSwap 10000 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(10000, 6),
      1,
      true,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 10000 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(10000, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 10000 USDC -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, DAI.address],
      Num(10000, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 10000 USDC -> WETH -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, wethAddress, DAI.address],
      Num(10000, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 10000 USDC -> WETH -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, wethAddress, DAI.address],
      Num(10000, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 10000 USDC -> USDT -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, USDT.address, DAI.address],
      Num(10000, 6),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 10000 USDC -> USDT -> DAI"
  try {
    checkedBalanceBefore = await DAI.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [USDC.address, USDT.address, DAI.address],
      Num(10000, 6),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(DAI);
  } catch(e) {
    console.log(logText, e.message);
  }

  console.log("--------------------------------------");

  // 50 DAI -> USDC
  logText = "singleSwap 50 DAI -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, USDC.address],
      Num(50, 18),
      1,
      true,
      false
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 50 DAI -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, USDC.address],
      Num(50, 18),
      1,
      true,
      true
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 50 DAI -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, USDC.address],
      Num(50, 18),
      1,
      false,
      false
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 50 DAI -> WETH -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, wethAddress, USDC.address],
      Num(50, 18),
      1,
      true,
      true
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 50 DAI -> WETH -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, wethAddress, USDC.address],
      Num(50, 18),
      1,
      false,
      false
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  console.log("--------------------------------------");

  // 1000 DAI -> USDC
  logText = "singleSwap 1000 DAI -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, USDC.address],
      Num(1000, 18),
      1,
      true,
      false
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 1000 DAI -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, USDC.address],
      Num(1000, 18),
      1,
      true,
      true
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 1000 DAI -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, USDC.address],
      Num(1000, 18),
      1,
      false,
      false
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 1000 DAI -> WETH -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, wethAddress, USDC.address],
      Num(1000, 18),
      1,
      true,
      true
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 1000 DAI -> WETH -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, wethAddress, USDC.address],
      Num(1000, 18),
      1,
      false,
      false
    );
    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  console.log("--------------------------------------");

  // 10000 DAI -> USDC
  logText = "singleSwap 10000 DAI -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, USDC.address],
      Num(10000, 18),
      1,
      true,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 10000 DAI -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, USDC.address],
      Num(10000, 18),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 10000 DAI -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, USDC.address],
      Num(10000, 18),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "multihopSwap 10000 DAI -> WETH -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, wethAddress, USDC.address],
      Num(10000, 18),
      1,
      true,
      true
    );

    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  logText = "sushiSwap 10000 DAI -> WETH -> USDC"
  try {
    checkedBalanceBefore = await USDC.balanceOf(cellar.address);
    tx = await cellar.swapForGasTest(
      [DAI.address, wethAddress, USDC.address],
      Num(10000, 18),
      1,
      false,
      false
    );

    gasUsedLog(logText, tx);
    amountOutLog(USDC);
  } catch(e) {
    console.log(logText, e.message);
  }

  console.log("--------------------------------------");

  await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

/*
 * Error: VM Exception while processing transaction: reverted with reason string 'SPL'
 *
 * bool zeroForOne = tokenIn < tokenOut;
 *
 * @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
 * uint160 internal constant MIN_SQRT_RATIO = 4295128739;
 * 
 * @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
 * uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
 *
 * sqrtPriceLimitX96 == 0
 *    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
 *    : sqrtPriceLimitX96
 *
 * require(
 *   zeroForOne
 *     ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
 *     : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
 *   'SPL'
 * );
 * 
 * slot0Start.sqrtPriceX96 is the current price.
 * 
 * sqrtPriceLimitX96 is the upper limit of the price. Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
 */

