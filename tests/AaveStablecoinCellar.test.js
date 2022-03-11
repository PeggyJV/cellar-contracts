const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("AaveStablecoinCellar", () => {
  let owner;
  let cellar;
  let usdc;
  let weth;
  let dai;
  let usdt;
  let router;
  let lendingPool;
  let aToken;
  let dataProvider;

  beforeEach(async () => {
    [owner] = await ethers.getSigners();

    // Deploy mock Uniswap router contract
    const SwapRouter = await ethers.getContractFactory("MockSwapRouter");
    router = await SwapRouter.deploy();
    await router.deployed();

    // Deploy mock Aave USDC lending pool
    const LendingPool = await ethers.getContractFactory("MockLendingPool");
    lendingPool = await LendingPool.deploy("USDC");
    await lendingPool.deployed();
    aToken = await ethers.getContractAt("MockToken", lendingPool.aToken());

    const MockAaveDataProvider = await ethers.getContractFactory(
      "MockAaveDataProvider"
    );
    dataProvider = await MockAaveDataProvider.deploy();
    await dataProvider.deployed();

    // Deploy cellar contract
    const AaveStablecoinCellar = await ethers.getContractFactory(
      "AaveStablecoinCellar"
    );
    cellar = await AaveStablecoinCellar.deploy(
      router.address,
      lendingPool.address,
      dataProvider.address,
      "Aave Stablecoin Cellar Inactive LP Token",
      "ASCCT"
    );
    await cellar.deployed();

    // Deploy mock tokens
    const Token = await ethers.getContractFactory("MockToken");
    usdc = await Token.deploy("USDC");
    dai = await Token.deploy("DAI");
    weth = await Token.deploy("WETH");
    usdt = await Token.deploy("USDT");

    await usdc.deployed();
    await dai.deployed();
    await weth.deployed();
    await usdt.deployed();

    // Mint mock tokens to owner
    await usdc.mint(owner.address, 100);
    await dai.mint(owner.address, 100);
    await weth.mint(owner.address, 100);
    await usdt.mint(owner.address, 100);

    // Approve cellar to spend mock tokens
    await usdc.approve(cellar.address, 100);
    await dai.approve(cellar.address, 100);
    await weth.approve(cellar.address, 100);
    await usdt.approve(cellar.address, 100);

    // Mint initial tokens to cellar
    await usdc.mint(cellar.address, 1000);
    await dai.mint(cellar.address, 1000);
    await weth.mint(cellar.address, 1000);
    await usdt.mint(cellar.address, 1000);

    // Mint initial liquidity to router
    await usdc.mint(router.address, 5000);
    await dai.mint(router.address, 5000);
    await weth.mint(router.address, 5000);
    await usdt.mint(router.address, 5000);

    // Initialize with mock tokens as input tokens
    await cellar.initInputToken(usdc.address);
    await cellar.initInputToken(dai.address);
    await cellar.initInputToken(weth.address);
    await cellar.initInputToken(usdt.address);
  });

  describe("addLiquidity", () => {
    it("should mint correct amount of inactive LP token to user", async () => {
      await cellar.addLiquidity(usdc.address, 100);
      expect(await cellar.balanceOf(owner.address)).to.eq(100);
    });

    it("should transfer input token from user to cellar", async () => {
      const beforeUserBalance = await usdc.balanceOf(owner.address);
      const beforeCellarBalance = await usdc.balanceOf(cellar.address);

      await cellar.addLiquidity(usdc.address, 100);

      const afterUserBalance = await usdc.balanceOf(owner.address);
      const afterCellarBalance = await usdc.balanceOf(cellar.address);
      expect(afterUserBalance - beforeUserBalance).to.eq(-100);
      expect(afterCellarBalance - beforeCellarBalance).to.eq(100);
    });
  });

  describe("swap", () => {
    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      await cellar.swap(usdc.address, dai.address, 1000, 950);
      expect(await usdc.balanceOf(cellar.address)).to.eq(0);
      expect(await dai.balanceOf(cellar.address)).to.be.at.least(950);

      expect(
        cellar.swap(usdc.address, dai.address, 1000, 2000)
      ).to.be.revertedWith("amountOutMin invariant failed");
    });
  });

  describe("multihopSwap", () => {
    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      await cellar.multihopSwap(
        [weth.address, usdc.address, usdt.address],
        1000,
        950
      );
      expect(await weth.balanceOf(cellar.address)).to.eq(0);
      expect(await usdt.balanceOf(cellar.address)).to.be.at.least(950);

      expect(
        cellar.swap(usdc.address, dai.address, 1000, 2000)
      ).to.be.revertedWith("amountOutMin invariant failed");
    });
    it("multihop swap with two tokens in the path", async () => {
      await cellar.multihopSwap([weth.address, dai.address], 1000, 950);
      expect(await weth.balanceOf(cellar.address)).to.eq(0);
      expect(await dai.balanceOf(cellar.address)).to.be.at.least(950);
    });

    it("multihop swap with four tokens in the path", async () => {
      await cellar.multihopSwap(
        [usdc.address, dai.address, weth.address, usdt.address],
        1000,
        950
      );
      expect(await usdc.balanceOf(cellar.address)).to.eq(0);
      expect(await usdt.balanceOf(cellar.address)).to.be.at.least(950);
    });
  });

  describe("enterStrategy", () => {
    beforeEach(async () => {
      await cellar.enterStrategy(usdc.address, 1000);
    });

    it("should deposit cellar holdings into lending pool", async () => {
      expect(await usdc.balanceOf(cellar.address)).to.eq(0);
      expect(await usdc.balanceOf(lendingPool.address)).to.eq(1000);
    });

    it("should return aTokens to cellar after depositing", async () => {
      expect(await aToken.balanceOf(cellar.address)).to.eq(1000);
    });

    xit("should convert inactive_lp_shares into active_lp_shares", async () => {
      // TODO: write test once implemented
    });
  });

  describe("redeemFromAave", () => {
    beforeEach(async () => {
      await cellar.enterStrategy(usdc.address, 1000);

      await cellar.redeemFromAave(usdc.address, 1000);
    });

    it("should return correct amount of tokens back to cellar from lending pool", async () => {
      expect(await usdc.balanceOf(cellar.address)).to.eq(1000);
    });

    it("should transfer correct amount of aTokens to lending pool", async () => {
      expect(await aToken.balanceOf(cellar.address)).to.eq(0);
    });
  });

  describe("rebalance", () => {
    beforeEach(async () => {
      await cellar.enterStrategy(usdc.address, 1000);
    });
    it("should rebalance all usdc liquidity in dai", async () => {
      await cellar.rebalance(dai.address);
      expect(await usdc.balanceOf(lendingPool.address)).to.eq(0);
      // After the swap,  amount of  coin will change from the exchange rate of 0.95
      expect(await dai.balanceOf(lendingPool.address)).to.eq(950);
    });

    it("should not be possible to rebalance to the same token", async () => {
      await expect(cellar.rebalance(usdc.address)).to.be.revertedWith(
        "SameLendingToken"
      );
    });
  });
});
