const hre = require("hardhat");
const ethers = hre.ethers;
const { alchemyApiKey } = require('../secrets.json');
const { expect } = require("chai");
require( "hardhat-gas-reporter")

describe("reinvest gas and profit estimate", () => {
  let blockNumber;
  
  let owner;
  let alice;

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

  const BALANCER_POOL_ID_USDC_WETH = "0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019";
  const BALANCER_POOL_ID_USDT_WETH = "0x3e5fa9518ea95c3e533eb377c001702a9aacaa32000200000000000000000052";
  const BALANCER_POOL_ID_DAI_WETH = "0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a";

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

  const enterStrategyAndClaim = async (depositAmount, token) => {
    console.log("deposit to cellar " + depositAmount + "$");
    await cellar["deposit(uint256,address)"](Num(depositAmount/2, (await cellar.assetDecimals())), owner.address);
    await cellar.connect(alice).deposit(Num(depositAmount/2, (await cellar.assetDecimals())), alice.address);

    if (token == DAI) {
      await cellar.rebalance(
        [
          USDC.address,
          curveStableSwap3PoolAddress,
          DAI.address,
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
        ],
        [
          [1, 0, 1], // [i, j, swap type], where i and j: 0 - DAI, 1 - USDC, 2 - USDT; swap type: 1 - for a stableswap `exchange`
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0]
        ],
        0
      );
    }  else if (token == USDT) {
      await cellar.rebalance(
        [
          USDC.address,
          curveStableSwap3PoolAddress,
          USDT.address,
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
        ],
        [
          [1, 2, 1], // [i, j, swap type], where i and j: 0 - DAI, 1 - USDC, 2 - USDT; swap type: 1 - for a stableswap `exchange`
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0]
        ],
        0
      );
    } else {
      await cellar.enterStrategy();
    }

    await cellar.accrueFees();

    console.log("timetravel 3 month");
    await timetravel(3*31*86400); // 3 month

    tx = await cellar.claimAndUnstake();
    await gasUsedLog("cellar.claimAndUnstake", tx);

    console.log("timetravel 10 day");
    await timetravel(10*86400); // 10 day
  };

  const Num = (number, decimals) => {
    const [characteristic, mantissa] = number.toString().split(".");
    const padding = mantissa ? decimals - mantissa.length : decimals;
    return characteristic + (mantissa ?? "") + "0".repeat(padding);
  };

  beforeEach(async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${alchemyApiKey}`,
            blockNumber: 14316384
          },
        },
      ],
    });
    
    blockNumber = await ethers.provider.getBlockNumber();
    console.log("The latest block number is", blockNumber);

    gasPrice = await ethers.provider.getGasPrice();
    console.log("gasPrice:", gasPrice);

    [owner, alice] = await ethers.getSigners();

    // set 1000000 ETH to owner balance
    await network.provider.send("hardhat_setBalance", [
        owner.address,
        ethers.utils.parseEther("1000000").toHexString(),
    ]);

    // set 1000000 ETH to alice balance
    await network.provider.send("hardhat_setBalance", [
        alice.address,
        ethers.utils.parseEther("1000000").toHexString(),
    ]);
    
    console.log(
      "Owner ETH balance:", (await ethers.provider.getBalance(owner.address)) / 10**18
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
    chainlinkETHUSDPriceFeed = await ethers.getContractAt("AggregatorInterface", chainlinkETHUSDPriceFeedAddress);
    ethPriceUSD = await chainlinkETHUSDPriceFeed.latestAnswer();
    console.log("ethPriceUSD: " + ethPriceUSD);

    // Aave Lending Pool contract
    lendingPool = await ethers.getContractAt("ILendingPool", lendingPoolAddress);
    
    // Uniswap V3 Router contract
    swapRouter = await ethers.getContractAt("ISwapRouter", routerAddress);
    
    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        USDC.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1649979765, // deadline
        Num(10000000, 6), // amountOut
        ethers.utils.parseEther("50000"), // amountInMaximum
        0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
      ],
      { value: ethers.utils.parseEther("50000") }
    );

    console.log("Owner USDC balance:", (await USDC.balanceOf(owner.address)) / 10**6);

    await swapRouter.connect(alice).exactOutputSingle(
      [
        wethAddress, // tokenIn
        USDC.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1649979765, // deadline
        Num(10000000, 6), // amountOut
        ethers.utils.parseEther("50000"), // amountInMaximum
        0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
      ],
      { value: ethers.utils.parseEther("50000") }
    );

    console.log("Alice USDC balance:", (await USDC.balanceOf(alice.address)) / 10**6);

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

    console.log("cellar.removeLiquidityRestriction");
    await cellar.removeLiquidityRestriction();

    await USDC.approve(
      cellar.address,
      ethers.constants.MaxUint256
    );

    await USDC.connect(alice).approve(
      cellar.address,
      ethers.constants.MaxUint256
    );
  });

  describe("Strategy with 100_000 USDC", () => {
    beforeEach(async () => {
      await enterStrategyAndClaim(100_000, USDC);
    });

    it("cellar.reinvest USDC", async () => {
      console.log("------------------- Test cellar.reinvest -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvest(0);
      await gasUsedLog("cellar.reinvest", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });
    
    it("cellar.reinvestHybrid USDC", async () => {
      console.log("------------------- Test cellar.reinvestHybrid -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestHybrid(0);
      await gasUsedLog("cellar.reinvestHybrid", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });

    it("cellar.reinvestBalancerProxyAndBalancerVault USDC", async () => {
      console.log("------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestBalancerProxyAndBalancerVault(0, BALANCER_POOL_USDC_WETH);
      await gasUsedLog("cellar.reinvestBalancerProxyAndBalancerVault", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });


  });
  
  describe("Strategy with 1_000_000 USDC", () => {
    beforeEach(async () => {
      await enterStrategyAndClaim(1_000_000, USDC);
    });

    it("cellar.reinvest USDC", async () => {
      console.log("------------------- Test cellar.reinvest -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvest(0);
      await gasUsedLog("cellar.reinvest", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });

    it("cellar.reinvestHybrid USDC", async () => {
      console.log("------------------- Test cellar.reinvestHybrid -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestHybrid(0);
      await gasUsedLog("cellar.reinvestHybrid", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });

    it("cellar.reinvestBalancerProxyAndBalancerVault USDC", async () => {
      console.log("------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestBalancerProxyAndBalancerVault(0, BALANCER_POOL_USDC_WETH);
      await gasUsedLog("cellar.reinvestBalancerProxyAndBalancerVault", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });


  });
  
  describe("Strategy with 8_000_000 USDC", () => {
    beforeEach(async () => {
      await enterStrategyAndClaim(8_000_000, USDC);
    });

    it("cellar.reinvest USDC", async () => {
      console.log("------------------- Test cellar.reinvest -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvest(0);
      await gasUsedLog("cellar.reinvest", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });

    it("cellar.reinvestHybrid USDC", async () => {
      console.log("------------------- Test cellar.reinvestHybrid -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestHybrid(0);
      await gasUsedLog("cellar.reinvestHybrid", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });

    it("cellar.reinvestBalancerProxyAndBalancerVault USDC", async () => {
      console.log("------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestBalancerProxyAndBalancerVault(0, BALANCER_POOL_ID_USDC_WETH);
      await gasUsedLog("cellar.reinvestHybrid", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });
  });
  
  describe("Strategy with 8_000_000 DAI", () => {
    beforeEach(async () => {
      await enterStrategyAndClaim(8_000_000, DAI);
    });

    it("cellar.reinvest DAI", async () => {
      console.log("------------------- Test cellar.reinvest -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvest(0);
      await gasUsedLog("cellar.reinvest", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });

    it("cellar.reinvestHybrid DAI", async () => {
      console.log("------------------- Test cellar.reinvestHybrid -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestHybrid(0);
      await gasUsedLog("cellar.reinvestHybrid", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });

    it("cellar.reinvestBalancerProxyAndBalancerVault DAI", async () => {
      console.log("------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestBalancerProxyAndBalancerVault(0, BALANCER_POOL_ID_DAI_WETH);
      await gasUsedLog("cellar.reinvestBalancerProxyAndBalancerVault", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });

  });

  describe("Strategy with 8_000_000 USDT", () => {
    beforeEach(async () => {
      await enterStrategyAndClaim(8_000_000, USDT);
    });

    it("cellar.reinvest USDT", async () => {
      console.log("------------------- Test cellar.reinvest -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvest(0);
      await gasUsedLog("cellar.reinvest", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });

    it("cellar.reinvestHybrid USDT", async () => {
      console.log("------------------- Test cellar.reinvestHybrid -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestHybrid(0);
      await gasUsedLog("cellar.reinvestHybrid", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });
    it("cellar.reinvestBalancerProxyAndBalancerVault USDT", async () => {
      console.log("------------------- Test cellar.reinvestBalancerProxyAndBalancerVault -------------------");
      totalAssetsUSD = (await cellar.totalAssets())/ 10**(await cellar.assetDecimals());
      console.log("totalAssets:", totalAssetsUSD.toFixed(2) + "$");

      tx = await cellar.reinvestBalancerProxyAndBalancerVault(0, BALANCER_POOL_ID_USDT_WETH);
      await gasUsedLog("cellar.reinvestBalancerProxyAndBalancerVault", tx);

      console.log("totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals())).toFixed(2) + "$");
      console.log("Difference totalAssets:", ((await cellar.totalAssets())/ 10**(await cellar.assetDecimals()) - totalAssetsUSD).toFixed(2) + "$");
    });
  });
});
