const hre = require("hardhat");
const ethers = hre.ethers;

let owner

let usdc
let usdt
let dai
let weth

let swapRouter
let cellar

let tx

// addresses of smart contracts in the mainnet
const routerAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564' // Uniswap V3 SwapRouter
// const sushiSwapRouterAddress = '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F' // SushiSwap V2 Router
const lendingPoolAddress = '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9' // Aave LendingPool
const dataProviderAddress = '0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d' // AaveProtocolDataProvider
const incentivesControllerAddress = '0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5' // StakedTokenIncentivesController
const stkAAVEAddress = '0x4da27a545c0c5B758a6BA100e3a049001de870f5' // StakedTokenV2Rev3

// addresses of tokens in the mainnet
const aaveAddress = '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9'
const usdcAddress = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
const usdtAddress = '0xdAC17F958D2ee523a2206206994597C13D831ec7'
const daiAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
const wethAddress = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'

const timetravel = async (addTime) => {
  await network.provider.send("evm_increaseTime", [addTime]);
  await network.provider.send("evm_mine");
}

const gasUsedLog = async (text, tx) => {
//   console.log("tx: " + JSON.stringify(tx, null, 4))

  let block = await ethers.provider.send(
    'eth_getBlockByNumber',
    [
      ethers.utils.hexValue(tx.blockNumber),
      true,
    ]
  );

//   console.log("block: " + JSON.stringify(block, null, 4))

  console.log(text + " tx.blockNumber: " + tx.blockNumber + ", gasUsed: " + parseInt(block.gasUsed, 16));
}

async function main() {
  const blockNumber = await ethers.provider.getBlockNumber();
  console.log("The latest block number is " + blockNumber);

  const gasPrice = await ethers.provider.getGasPrice();
  console.log("gasPrice: " + gasPrice);

  [owner] = await ethers.getSigners();

  // set 100000 ETH to owner balance
  await network.provider.send("hardhat_setBalance", [
    owner.address,
    ethers.utils.parseEther("100000").toHexString(),
  ]);

  console.log("Owner ETH balance: " + await ethers.provider.getBalance(owner.address));

  // stablecoins contracts
  const Token = await ethers.getContractFactory("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20");
  usdc = await Token.attach(usdcAddress);
  usdt = await Token.attach(usdtAddress);
  dai = await Token.attach(daiAddress);

  // WETH contract
  weth = new ethers.Contract(
    wethAddress,
    [
      "function deposit() external payable",
      "function transfer(address to, uint value) external returns (bool)",
      "function withdraw(uint256 value) external payable",
      "function balanceOf(address account) external view returns (uint256)",
      "function approve(address spender, uint256 amount) external returns (bool)"
    ], 
    owner
  );

  // test weth.deposit
  await weth.deposit({"value": ethers.utils.parseEther("10")});

  console.log("Owner WETH balance: " + await weth.balanceOf(owner.address));

  // uniswap v3 router contract
  swapRouter = await ethers.getContractAt("ISwapRouter", routerAddress);

  // test swapRouter.exactInputSingle
  tx = await swapRouter.exactInputSingle(
    [
      weth.address, // tokenIn
      usdt.address, // tokenOut
      3000, // fee
      owner.address, // recipient
      1647479474, // deadline
      ethers.utils.parseEther("10"), // amountIn
      0, // amountOutMinimum
      0 // sqrtPriceLimitX96
    ],
    {"value": ethers.utils.parseEther("10")}
  );

  gasUsedLog('swapRouter.exactInputSingle', tx);
  console.log("Owner USDT balance: " + await usdt.balanceOf(owner.address));

  // test swapRouter.exactOutputSingle
  tx = await swapRouter.exactOutputSingle(
    [
      weth.address, // tokenIn
      usdc.address, // tokenOut
      3000, // fee
      owner.address, // recipient
      1647479474, // deadline
      ethers.BigNumber.from(10).pow(6).mul(1000), // amountOut
      ethers.utils.parseEther("10"), // amountInMaximum
      0 // sqrtPriceLimitX96
    ],
    {"value": ethers.utils.parseEther("10")}
  );

  gasUsedLog('swapRouter.exactOutputSingle', tx);
  console.log("Owner USDC balance: " + await usdc.balanceOf(owner.address));

  await swapRouter.exactOutputSingle(
    [
      weth.address, // tokenIn
      dai.address, // tokenOut
      3000, // fee
      owner.address, // recipient
      1647479474, // deadline
      ethers.BigNumber.from(10).pow(18).mul(1000), // amountOut
      ethers.utils.parseEther("10"), // amountInMaximum
      0 // sqrtPriceLimitX96
    ],
    {"value": ethers.utils.parseEther("10")}
  );

  console.log("Owner DAI balance: " + await dai.balanceOf(owner.address));

  // Deploy cellar contract
  const AaveStablecoinCellar = await ethers.getContractFactory(
    "AaveStablecoinCellar"
  );

  cellar = await AaveStablecoinCellar.deploy(
    routerAddress,
//     sushiSwapRouterAddress,
    lendingPoolAddress,
    dataProviderAddress,
    incentivesControllerAddress,
    stkAAVEAddress,
    aaveAddress,
    weth.address,
    usdc.address,
    usdc.address,
    "Sommelier Aave Stablecoin Cellar LP Token",
    "SASCT"
  );
  await cellar.deployed();

  await cellar.setInputToken(weth.address, true);
  await cellar.setInputToken(usdc.address, true);
  await cellar.setInputToken(usdt.address, true);
  await cellar.setInputToken(dai.address, true);

  await weth.approve(cellar.address, ethers.BigNumber.from(10).pow(18).mul(10000));
  await usdc.approve(cellar.address, ethers.BigNumber.from(10).pow(6).mul(10000));
  await usdt.approve(cellar.address, ethers.BigNumber.from(10).pow(6).mul(10000));
  await dai.approve(cellar.address, ethers.BigNumber.from(10).pow(18).mul(10000));

  tx = await cellar["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(500));
  gasUsedLog('cellar.deposit', tx);

  tx = await cellar.swap(usdc.address, dai.address, ethers.BigNumber.from(10).pow(6).mul(50), 0);
  gasUsedLog('cellar.swap', tx);

  tx = await cellar.multihopSwap([usdc.address, dai.address], ethers.BigNumber.from(10).pow(6).mul(50), 0);
  gasUsedLog('cellar.multihopSwap', tx);

  tx = await cellar.sushiswap([usdc.address, dai.address], ethers.BigNumber.from(10).pow(6).mul(50), 0);
  gasUsedLog('cellar.sushiswap', tx);
  
  tx = await cellar.enterStrategy();
  gasUsedLog('cellar.enterStrategy', tx);

  await cellar["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(100));
  await cellar["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(100));
  await cellar["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(100));
  await cellar["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(100));

  tx = await cellar["withdraw(uint256)"](ethers.BigNumber.from(10).pow(6).mul(700));
  gasUsedLog('cellar.withdraw', tx);

  await cellar["deposit(uint256)"](ethers.BigNumber.from(10).pow(6).mul(200));
  await cellar.enterStrategy();

  tx = await cellar.redeemFromAave(usdc.address, ethers.BigNumber.from(10).pow(6).mul(100));
  gasUsedLog('cellar.redeemFromAave', tx);

  tx = await cellar.rebalance(dai.address, 0);
  gasUsedLog('cellar.rebalance', tx);

  await cellar.redeemFromAave(dai.address, ethers.BigNumber.from(10).pow(18).mul(50));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
