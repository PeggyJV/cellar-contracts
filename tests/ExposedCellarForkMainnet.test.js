const hre = require("hardhat");
const { expect } = require("chai");
const { BigNumber } = require("ethers");
const ethers = hre.ethers;
const { alchemyApiKey } = require('../secrets.json');

describe("AaveV2StablecoinCellar", () => {
  let owner;
  let alice;

  let usdc;
  let usdt;
  let dai;

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

  const timetravel = async (addTime) => {
    await network.provider.send("evm_increaseTime", [addTime]);
    await network.provider.send("evm_mine");
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
    usdc = await Token.attach(usdcAddress);
    usdt = await Token.attach(usdtAddress);
    dai = await Token.attach(daiAddress);
    aave = await Token.attach(aaveAddress);
    aUSDC = await Token.attach(aUSDCAddress);

    // uniswap v3 router contract
    swapRouter = await ethers.getContractAt("ISwapRouter", routerAddress);

    // Deploy cellar contract
    const AaveV2StablecoinCellar = await ethers.getContractFactory(
      "$AaveV2StablecoinCellar"
    );

    cellar = await AaveV2StablecoinCellar.deploy(
      routerAddress,
      sushiSwapRouterAddress,
      lendingPoolAddress,
      incentivesControllerAddress,
      gravityBridgeAddress,
      stkAAVEAddress,
      aaveAddress,
      wethAddress,
      usdc.address,
      usdc.address
    );
    await cellar.deployed();

    await cellar.setInputToken(usdc.address, true);
    await cellar.setInputToken(usdt.address, true);
    await cellar.setInputToken(dai.address, true);

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        usdc.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1657479474, // deadline
        Num(1000, 6), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        dai.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1657479474, // deadline
        Num(1000, 18), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        usdt.address, // tokenOut
        3000, // fee
        owner.address, // recipient
        1657479474, // deadline
        Num(1000, 6), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        usdc.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1657479474, // deadline
        Num(1000, 6), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        dai.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1657479474, // deadline
        Num(1000, 18), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await swapRouter.exactOutputSingle(
      [
        wethAddress, // tokenIn
        usdt.address, // tokenOut
        3000, // fee
        alice.address, // recipient
        1657479474, // deadline
        Num(1000, 6), // amountOut
        ethers.utils.parseEther("10"), // amountInMaximum
        0, // sqrtPriceLimitX96
      ],
      { value: ethers.utils.parseEther("10") }
    );

    await usdc.approve(
      cellar.address,
      Num(10000, 6)
    );
    await usdt.approve(
      cellar.address,
      Num(10000, 6)
    );
    await dai.approve(
      cellar.address,
      Num(10000, 18)
    );

    await usdc
      .connect(alice)
      .approve(cellar.address, Num(10000, 6));
    await dai
      .connect(alice)
      .approve(cellar.address, Num(10000, 18));
    await usdt
      .connect(alice)
      .approve(cellar.address, Num(10000, 6));

    // balances accumulate every test
  });

  describe("_redeemFromAave", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256)"](Num(1000, 6));

      await cellar.enterStrategy();

      await timetravel(864000); // 10 day

      await cellar.$_redeemFromAave(usdc.address, Num(1000.76698, 6)); // deposit + income
    });

    it("should return correct amount of tokens back to cellar from lending pool", async () => {
      expect(await usdc.balanceOf(cellar.address)).to.eq(Num(1000.76698, 6));
    });

    it("should transfer correct amount of aTokens to lending pool", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
    });
    
    it("should not allow redeeming more than cellar deposited", async () => {
      // cellar tries to redeem $100 when it should have deposit balance of $0
      await expect(cellar.$_redeemFromAave(usdc.address, Num(100, 6))).to.be.reverted;
    });

    it("should emit RedeemFromAave event", async () => {
      await cellar.connect(alice)["deposit(uint256)"](Num(1000, 6));
      await cellar.enterStrategy();

      await expect(cellar.$_redeemFromAave(usdc.address, Num(1000, 6)))
        .to.emit(cellar, "RedeemFromAave")
        .withArgs(usdc.address, Num(1000, 6));
    });
  });

  describe("simple swap", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256)"](
        Num(1000, 6)
      );

      await cellar
        .connect(alice)
        ["deposit(uint256)"](Num(1000, 6));
    });

    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      await cellar.$_swap([usdc.address, dai.address], Num(1000, 6), 0, true);
      expect(await usdc.balanceOf(cellar.address)).to.eq(Num(1000, 6));
      expect(await dai.balanceOf(cellar.address)).to.be.at.least(Num(950, 18));

      // expect fail if minimum amount of output tokens not received
      await expect(
        cellar.$_swap([usdc.address, dai.address], Num(1000, 6), Num(2000, 18), true)
      ).to.be.revertedWith("Too little received");
    });

    it("should revert if trying to swap more tokens than cellar has", async () => {
      await expect(
        cellar.$_swap([usdc.address, dai.address], Num(3000, 6), Num(1800, 18), true)
      ).to.be.revertedWith("STF");
    });

    it("should emit Swapped event", async () => {
      await expect(cellar.$_swap([usdc.address, dai.address], Num(1000, 6), Num(950, 18), true))
        .to.emit(cellar, "Swapped")
        .withArgs(usdc.address, Num(1000, 6), dai.address, '994678811179279068938');
    });
  });

  describe("multihop swap", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256)"](
        Num(1000, 6)
      );

      await cellar
        .connect(alice)
        ["deposit(uint256)"](Num(1000, 6));
    });

    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      const balanceUSDCBefore = await usdc.balanceOf(cellar.address);
      const balanceUSDTBefore = await usdt.balanceOf(cellar.address);

      await cellar.$_swap(
        [usdc.address, wethAddress, usdt.address],
        Num(1000, 6),
        Num(950, 6),
        true
      );

      expect(balanceUSDTBefore).to.eq(0);
      expect(await usdc.balanceOf(cellar.address)).to.eq(
        balanceUSDCBefore - Num(1000, 6)
      );
      expect(await usdt.balanceOf(cellar.address)).to.be.at.least(
        balanceUSDTBefore + Num(950, 6)
      );

      await expect(
        cellar.$_swap(
          [usdc.address, wethAddress, dai.address],
          Num(1000, 6),
          Num(2000, 18),
          true
        )
      ).to.be.revertedWith("Too little received");
    });

    it("multihop swap with more than three tokens in the path", async () => {
      const balanceUSDCBefore = await usdc.balanceOf(cellar.address);
      const balanceUSDTBefore = await usdt.balanceOf(cellar.address);

      await cellar.$_swap(
        [usdc.address, wethAddress, dai.address, wethAddress, usdt.address],
        Num(1000, 6),
        Num(950, 6),
        true
      );
      expect(await usdc.balanceOf(cellar.address)).to.eq(
        balanceUSDCBefore - Num(1000, 6)
      );
      expect(await usdt.balanceOf(cellar.address)).to.be.at.least(
        balanceUSDTBefore + Num(950, 6)
      );
    });

    it("should revert if trying to swap more tokens than cellar has", async () => {
      await expect(
        cellar.$_swap(
          [usdc.address, wethAddress, dai.address],
          Num(3000, 6),
          Num(2800, 18),
          true
        )
      ).to.be.revertedWith("STF");
    });

    it("should emit Swapped event", async () => {
      await expect(
        cellar.$_swap(
          [usdc.address, wethAddress, dai.address],
          Num(1000, 6),
          Num(950, 18),
          true
        )
      )
        .to.emit(cellar, "Swapped")
        .withArgs(usdc.address, Num(1000, 6), dai.address, '992792014394087097233');
    });
  });
  
  describe("sushi swap", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256)"](
        Num(1000, 6)
      );

      await cellar
        .connect(alice)
        ["deposit(uint256)"](Num(1000, 6));
    });

    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      const balanceUSDCBefore = await usdc.balanceOf(cellar.address);
      const balanceUSDTBefore = await usdt.balanceOf(cellar.address);

      await cellar.$_swap(
        [usdc.address, wethAddress, usdt.address],
        Num(1000, 6),
        Num(950, 6),
        false
      );

      expect(balanceUSDTBefore).to.eq(0);
      expect(await usdc.balanceOf(cellar.address)).to.eq(
        balanceUSDCBefore - Num(1000, 6)
      );
      expect(await usdt.balanceOf(cellar.address)).to.be.at.least(
        balanceUSDTBefore + Num(950, 6)
      );

      await expect(
        cellar.$_swap(
          [usdc.address, wethAddress, dai.address],
          Num(1000, 6),
          Num(2000, 18),
          false
        )
      ).to.be.revertedWith("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
    });

    it("sushi swap with more than three tokens in the path", async () => {
      const balanceUSDCBefore = await usdc.balanceOf(cellar.address);

      await cellar.$_swap(
        [usdc.address, usdt.address, wethAddress, aave.address],
        Num(1000, 6),
        Num(3, 18),
        false
      );

      expect(await usdc.balanceOf(cellar.address)).to.eq(
        balanceUSDCBefore - Num(1000, 6)
      );
      expect(await aave.balanceOf(cellar.address)).to.eq('3364818494631116837');

      const balanceAAVEBefore = await aave.balanceOf(cellar.address);

      await cellar.$_swap(
        [usdc.address, usdt.address, dai.address, wethAddress, aave.address],
        Num(1000, 6),
        0,
        false
      );

      expect(await usdc.balanceOf(cellar.address)).to.eq(0);
      expect((await aave.balanceOf(cellar.address)).sub(balanceAAVEBefore)).to.eq(
        '568434953405847983' // since the path is long, the exchange is very unprofitable
      );
    });

    it("should raise an error for a path containing the token repetition through one element", async () => {
      await expect(
        cellar.$_swap(
          [usdc.address, wethAddress, usdc.address],
          Num(1000, 6),
          Num(900, 6),
          false
        )
      ).to.be.revertedWith("UniswapV2: INSUFFICIENT_INPUT_AMOUNT");

      await cellar.$_swap(
        [usdc.address, wethAddress, dai.address, usdc.address],
        Num(1000, 6),
        Num(900, 6),
        false
      );

      expect(await usdc.balanceOf(cellar.address)).to.eq(Num(1950.581410, 6));
    });

    it("should revert if trying to swap more tokens than cellar has", async () => {
      await expect(
        cellar.$_swap(
          [usdc.address, wethAddress, dai.address],
          Num(3000, 6),
          Num(2800, 18),
          false
        )
      ).to.be.revertedWith("TransferHelper: TRANSFER_FROM_FAILED");
    });

    it("should emit Swapped event", async () => {
      await expect(
        cellar.$_swap(
          [usdc.address, wethAddress, dai.address],
          Num(1000, 6),
          Num(950, 18),
          false
        )
      )
        .to.emit(cellar, "Swapped")
        .withArgs(usdc.address, Num(1000, 6), dai.address, '993876181130894899796');
    });
  });
});
