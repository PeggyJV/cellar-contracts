const hre = require("hardhat");
const { expect } = require("chai");
const { BigNumber } = require("ethers");
const ethers = hre.ethers;
const { alchemyApiKey } = require('../secrets.json');

describe("AaveV2StablecoinCellar", () => {
  let owner;
  let alice;

  let USDC;
  let USDT;
  let DAI;

  let aUSDC;

  let swapRouter;
  let cellar;

  // addresses of smart contracts in the mainnet
  const routerAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564"; // Uniswap V3 SwapRouter
  const sushiSwapRouterAddress = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F" // SushiSwap V2 Router
  const lendingPoolAddress = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9"; // Aave LendingPool
  const incentivesControllerAddress =
    "0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5"; // StakedTokenIncentivesController
  const gravityBridgeAddress = "0x69592e6f9d21989a043646fE8225da2600e5A0f7" // Cosmos Gravity Bridge contract
  const stkAAVEAddress = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"; // StakedTokenV2Rev3

  // addresses of tokens in the mainnet
  const aaveAddress = "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9";
  const usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const usdtAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
  const daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const aUSDCAddress = "0xBcca60bB61934080951369a648Fb03DF4F96263C";

  const timestamp = async () => {
    const latestBlock = await ethers.provider.getBlock(
      await ethers.provider.getBlockNumber()
    );

    return latestBlock.timestamp;
  };

  const timetravel = async (addTime) => {
    await network.provider.send("evm_increaseTime", [addTime]);
    await network.provider.send("evm_mine");
  };

  const Num = (number, decimals) => {
    const [characteristic, mantissa] = number.toString().split(".");
    const padding = mantissa ? decimals - mantissa.length : decimals;
    return characteristic + (mantissa ?? "") + "0".repeat(padding);
  };

  const initSwap = async (accaunt, token, amount) => {
    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        token.address, // tokenOut
        3000, // fee
        accaunt.address, // recipient
        (await timestamp()) + 50, // deadline
        Num(amount, (await token.decimals())), // amountOut
        ethers.utils.parseEther("1000"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("1000") }
    );
  };

  beforeEach(async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${alchemyApiKey}`,
            blockNumber: 13837533
          },
        },
      ],
    });

    [owner, alice] = await ethers.getSigners();

    // stablecoins contracts
    const Token = await ethers.getContractFactory(
      "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"
    );
    USDC = await Token.attach(usdcAddress);
    USDT = await Token.attach(usdtAddress);
    DAI = await Token.attach(daiAddress);
    AAVE = await Token.attach(aaveAddress);
    aUSDC = await Token.attach(aUSDCAddress);

    // uniswap v3 router contract
    swapRouter = await ethers.getContractAt("ISwapRouter", routerAddress);

    // Deploy cellar contract
    const AaveV2StablecoinCellar = await ethers.getContractFactory(
      "$AaveV2StablecoinCellar"
    );

    cellar = await AaveV2StablecoinCellar.deploy(
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

    await initSwap(owner, USDC, 1000);
    await initSwap(owner, DAI, 1000);
    await initSwap(owner, USDT, 1000);

    await initSwap(alice, USDC, 1000);
    await initSwap(alice, DAI, 1000);
    await initSwap(alice, USDT, 1000);

    await USDC.approve(
      cellar.address,
      ethers.constants.MaxUint256
    );
    await USDT.approve(
      cellar.address,
      ethers.constants.MaxUint256
    );
    await DAI.approve(
      cellar.address,
      ethers.constants.MaxUint256
    );

    await USDC
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);
    await DAI
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);
    await USDT
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);

    await cellar.approve(cellar.address, ethers.constants.MaxUint256);
    await cellar
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);
  });

  describe("_withdrawFromAave", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      await cellar.enterStrategy();

      await timetravel(864000); // 10 day

      await cellar.$_withdrawFromAave(USDC.address, Num(1000.76698, 6)); // deposit + income
    });

    it("should return correct amount of tokens back to cellar from lending pool", async () => {
      expect(await USDC.balanceOf(cellar.address)).to.eq(Num(1000.76698, 6));
    });

    it("should transfer correct amount of aTokens to lending pool", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
    });

    it("should not allow redeeming more than cellar deposited", async () => {
      // cellar tries to redeem $100 when it should have deposit balance of $0
      await expect(cellar.$_withdrawFromAave(USDC.address, Num(100, 6))).to.be.reverted;
    });

    it("should emit WithdrawFromAave event", async () => {
      await cellar.connect(alice)["deposit(uint256,address)"](Num(1000, 6), alice.address);
      await cellar.enterStrategy();

      await expect(cellar.$_withdrawFromAave(USDC.address, Num(1000, 6)))
        .to.emit(cellar, "WithdrawFromAave")
        .withArgs(USDC.address, Num(1000, 6));
    });
  });

  describe("simple swap", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(1000, 6), alice.address);
    });

    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      await cellar.$_swap([USDC.address, DAI.address], Num(1000, 6), 0, true);
      expect(await USDC.balanceOf(cellar.address)).to.eq(Num(1000, 6));
      expect(await DAI.balanceOf(cellar.address)).to.be.at.least(Num(950, 18));

      // expect fail if minimum amount of output tokens not received
      await expect(
        cellar.$_swap([USDC.address, DAI.address], Num(1000, 6), Num(2000, 18), true)
      ).to.be.revertedWith("Too little received");
    });

    it("should revert if trying to swap more tokens than cellar has", async () => {
      await expect(
        cellar.$_swap([USDC.address, DAI.address], Num(3000, 6), Num(1800, 18), true)
      ).to.be.revertedWith("STF");
    });

    it("should emit Swap event", async () => {
      await expect(cellar.$_swap([USDC.address, DAI.address], Num(1000, 6), Num(950, 18), true))
        .to.emit(cellar, "Swap")
        .withArgs(USDC.address, Num(1000, 6), DAI.address, '994678811179279068938');
    });
  });

  describe("multihop swap", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(1000, 6), alice.address);
    });

    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      const balanceUSDCBefore = await USDC.balanceOf(cellar.address);
      const balanceUSDTBefore = await USDT.balanceOf(cellar.address);

      await cellar.$_swap(
        [USDC.address, wethAddress, USDT.address],
        Num(1000, 6),
        Num(950, 6),
        true
      );

      expect(balanceUSDTBefore).to.eq(0);
      expect(await USDC.balanceOf(cellar.address)).to.eq(
        balanceUSDCBefore - Num(1000, 6)
      );
      expect(await USDT.balanceOf(cellar.address)).to.be.at.least(
        balanceUSDTBefore + Num(950, 6)
      );

      await expect(
        cellar.$_swap(
          [USDC.address, wethAddress, DAI.address],
          Num(1000, 6),
          Num(2000, 18),
          true
        )
      ).to.be.revertedWith("Too little received");
    });

    it("multihop swap with more than three tokens in the path", async () => {
      const balanceUSDCBefore = await USDC.balanceOf(cellar.address);
      const balanceUSDTBefore = await USDT.balanceOf(cellar.address);

      await cellar.$_swap(
        [USDC.address, wethAddress, DAI.address, wethAddress, USDT.address],
        Num(1000, 6),
        Num(950, 6),
        true
      );
      expect(await USDC.balanceOf(cellar.address)).to.eq(
        balanceUSDCBefore - Num(1000, 6)
      );
      expect(await USDT.balanceOf(cellar.address)).to.be.at.least(
        balanceUSDTBefore + Num(950, 6)
      );
    });

    it("should revert if trying to swap more tokens than cellar has", async () => {
      await expect(
        cellar.$_swap(
          [USDC.address, wethAddress, DAI.address],
          Num(3000, 6),
          Num(2800, 18),
          true
        )
      ).to.be.revertedWith("STF");
    });

    it("should emit Swap event", async () => {
      await expect(
        cellar.$_swap(
          [USDC.address, wethAddress, DAI.address],
          Num(1000, 6),
          Num(950, 18),
          true
        )
      )
        .to.emit(cellar, "Swap")
        .withArgs(USDC.address, Num(1000, 6), DAI.address, '992792014394087097233');
    });
  });

  describe("sushi swap", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(1000, 6), alice.address);
    });

    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      const balanceUSDCBefore = await USDC.balanceOf(cellar.address);
      const balanceUSDTBefore = await USDT.balanceOf(cellar.address);

      await cellar.$_swap(
        [USDC.address, wethAddress, USDT.address],
        Num(1000, 6),
        Num(950, 6),
        false
      );

      expect(balanceUSDTBefore).to.eq(0);
      expect(await USDC.balanceOf(cellar.address)).to.eq(
        balanceUSDCBefore - Num(1000, 6)
      );
      expect(await USDT.balanceOf(cellar.address)).to.be.at.least(
        balanceUSDTBefore + Num(950, 6)
      );

      await expect(
        cellar.$_swap(
          [USDC.address, wethAddress, DAI.address],
          Num(1000, 6),
          Num(2000, 18),
          false
        )
      ).to.be.revertedWith("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
    });

    it("sushi swap with more than three tokens in the path", async () => {
      const balanceUSDCBefore = await USDC.balanceOf(cellar.address);

      await cellar.$_swap(
        [USDC.address, USDT.address, wethAddress, AAVE.address],
        Num(1000, 6),
        Num(3, 18),
        false
      );

      expect(await USDC.balanceOf(cellar.address)).to.eq(
        balanceUSDCBefore - Num(1000, 6)
      );
      expect(await AAVE.balanceOf(cellar.address)).to.eq('3364818494631116837');

      const balanceAAVEBefore = await AAVE.balanceOf(cellar.address);

      await cellar.$_swap(
        [USDC.address, USDT.address, DAI.address, wethAddress, AAVE.address],
        Num(1000, 6),
        0,
        false
      );

      expect(await USDC.balanceOf(cellar.address)).to.eq(0);
      expect((await AAVE.balanceOf(cellar.address)).sub(balanceAAVEBefore)).to.eq(
        '568434953405847983' // since the path is long, the exchange is very unprofitable
      );
    });

    it("should raise an error for a path containing the token repetition through one element", async () => {
      await expect(
        cellar.$_swap(
          [USDC.address, wethAddress, USDC.address],
          Num(1000, 6),
          Num(900, 6),
          false
        )
      ).to.be.revertedWith("UniswapV2: INSUFFICIENT_INPUT_AMOUNT");

      await cellar.$_swap(
        [USDC.address, wethAddress, DAI.address, USDC.address],
        Num(1000, 6),
        Num(900, 6),
        false
      );

      expect(await USDC.balanceOf(cellar.address)).to.eq(Num(1950.581410, 6));
    });

    it("should revert if trying to swap more tokens than cellar has", async () => {
      await expect(
        cellar.$_swap(
          [USDC.address, wethAddress, DAI.address],
          Num(3000, 6),
          Num(2800, 18),
          false
        )
      ).to.be.revertedWith("TransferHelper: TRANSFER_FROM_FAILED");
    });

    it("should emit Swap event", async () => {
      await expect(
        cellar.$_swap(
          [USDC.address, wethAddress, DAI.address],
          Num(1000, 6),
          Num(950, 18),
          false
        )
      )
        .to.emit(cellar, "Swap")
        .withArgs(USDC.address, Num(1000, 6), DAI.address, '993876181130894899796');
    });
  });
});
