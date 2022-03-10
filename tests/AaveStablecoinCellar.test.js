const { ethers } = require("hardhat");
const { expect } = require("chai");
const { BigNumber } = require("ethers");

describe("AaveStablecoinCellar", () => {
  let owner;
  let alice;
  let cellar;
  let usdc;
  let dai;
  let router;
  let lendingPool;
  let aUSDC;

  beforeEach(async () => {
    [owner, alice] = await ethers.getSigners();

    // Deploy mock Uniswap router contract
    const SwapRouter = await ethers.getContractFactory("MockSwapRouter");
    router = await SwapRouter.deploy();
    await router.deployed();

    // Deploy mock tokens
    const Token = await ethers.getContractFactory("MockToken");
    usdc = await Token.deploy("USDC");
    dai = await Token.deploy("DAI");
    weth = await Token.deploy("WETH");
    await usdc.deployed();
    await dai.deployed();
    await weth.deployed();

    // Deploy mock aUSDC
    const MockAToken = await ethers.getContractFactory("MockAToken");
    aUSDC = await MockAToken.deploy(usdc.address, "aUSDC");
    await aUSDC.deployed();

    // Deploy mock Aave USDC lending pool
    const LendingPool = await ethers.getContractFactory("MockLendingPool");
    lendingPool = await LendingPool.deploy(aUSDC.address);
    await lendingPool.deployed();

    // Deploy cellar contract
    const AaveStablecoinCellar = await ethers.getContractFactory(
      "AaveStablecoinCellar"
    );
    cellar = await AaveStablecoinCellar.deploy(
      router.address,
      lendingPool.address,
      usdc.address,
      "Sommelier Aave Stablecoin Cellar LP Token",
      "SASCT"
    );
    await cellar.deployed();

    // Mint mock tokens to signers
    await usdc.mint(owner.address, 1000);
    await dai.mint(owner.address, 1000);
    await weth.mint(owner.address, 1000);

    await usdc.mint(alice.address, 1000);
    await dai.mint(alice.address, 1000);
    await weth.mint(alice.address, 1000);

    // Approve cellar to spend mock tokens
    await usdc.approve(cellar.address, 1000);
    await dai.approve(cellar.address, 1000);
    await weth.approve(cellar.address, 1000);

    await usdc.connect(alice).approve(cellar.address, 1000);
    await dai.connect(alice).approve(cellar.address, 1000);
    await weth.connect(alice).approve(cellar.address, 1000);

    // Mint initial liquidity to Aave USDC lending pool
    await usdc.mint(aUSDC.address, 5000);

    // Mint initial liquidity to router
    await usdc.mint(router.address, 5000);
    await dai.mint(router.address, 5000);
    await weth.mint(router.address, 5000);

    // Initialize with mock tokens as input tokens
    await cellar.initInputToken(usdc.address);
    await cellar.initInputToken(dai.address);
    await cellar.initInputToken(weth.address);
  });

  describe("deposit", () => {
    it("should mint correct amount of inactive LP token to user", async () => {
      // add $100 of inactive assets in cellar
      await cellar["deposit(uint256)"](100);
      // expect 100 shares to be minted (because total supply of shares is 0)
      expect(await cellar.balanceOf(owner.address)).to.eq(100);

      // add $50 of inactive assets in cellar
      await cellar.connect(alice)["deposit(uint256)"](50);
      // expect 50 shares = 100 total shares * ($50 / $100) to be minted
      expect(await cellar.balanceOf(alice.address)).to.eq(50);
    });

    it("should transfer input token from user to cellar", async () => {
      const initialUserBalance = await usdc.balanceOf(owner.address);
      const initialCellarBalance = await usdc.balanceOf(cellar.address);

      await cellar["deposit(uint256)"](100);

      const updatedUserBalance = await usdc.balanceOf(owner.address);
      const updatedCellarBalance = await usdc.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner to cellar
      expect(updatedUserBalance - initialUserBalance).to.eq(-100);
      expect(updatedCellarBalance - initialCellarBalance).to.eq(100);
    });
  });

  describe("withdraw", () => {
    beforeEach(async () => {
      // both owner and alice should start off owning 50% of the cellar's total assets each
      await cellar["deposit(uint256)"](100);
      await cellar.connect(alice)["deposit(uint256)"](100);
    });

    it("should withdraw correctly when called with all inactive shares", async () => {
      const ownerInitialBalance = await usdc.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $100 (50% of total)
      await cellar["withdraw(uint256)"](100);
      const ownerUpdatedBalance = await usdc.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerUpdatedBalance - ownerInitialBalance).to.eq(100);
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceInitialBalance = await usdc.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $100 (50% of total)
      await cellar.connect(alice)["withdraw(uint256)"](100);
      const aliceUpdatedBalance = await usdc.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect(aliceUpdatedBalance - aliceInitialBalance).to.eq(100);
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with all active shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy(usdc.address, 200);

      // mimic growth from $200 -> $250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(
        BigNumber.from("1250000000000000000000000000")
      );

      const ownerInitialBalance = await usdc.balanceOf(owner.address);
      // owner should be able redeem all shares for $125 (50% of total)
      await cellar["withdraw(uint256)"](125);
      const ownerUpdatedBalance = await usdc.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerUpdatedBalance - ownerInitialBalance).to.eq(125);
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceInitialBalance = await usdc.balanceOf(alice.address);
      // alice should be able redeem all shares for $125 (50% of total)
      await cellar.connect(alice)["withdraw(uint256)"](125);
      const aliceUpdatedBalance = await usdc.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect(aliceUpdatedBalance - aliceInitialBalance).to.eq(125);
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with active and inactive shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy(usdc.address, 200);

      // mimic growth from $200 -> $250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(
        BigNumber.from("1250000000000000000000000000")
      );

      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](100);
      // alice adds $75 of inactive assets
      await cellar.connect(alice)["deposit(uint256)"](75);

      const ownerInitialBalance = await usdc.balanceOf(owner.address);
      // owner should be able redeem all shares for $225 ($125 active + $100 inactive)
      await cellar["withdraw(uint256)"](225);
      const ownerUpdatedBalance = await usdc.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerUpdatedBalance - ownerInitialBalance).to.eq(225);
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceInitialBalance = await usdc.balanceOf(alice.address);
      // alice should be able redeem all shares for $200 ($125 active + $75 inactive)
      await cellar.connect(alice)["withdraw(uint256)"](200);
      const aliceUpdatedBalance = await usdc.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect(aliceUpdatedBalance - aliceInitialBalance).to.eq(200);
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should use and store index of first non-zero deposit", async () => {
      // owner withdraws everything from deposit object at index 0
      await cellar["withdraw(uint256)"](100);
      // expect next non-zero deposit is set to index 1
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(1);

      // alice only withdraws half from index 0, leaving some shares remaining
      await cellar.connect(alice)["withdraw(uint256)"](50);
      // expect next non-zero deposit is set to index 0 since some shares still remain
      expect(await cellar.currentDepositIndex(alice.address)).to.eq(0);
    });

    it("should revert if user tries to withdraw more assets than they have", async () => {
      await cellar["withdraw(uint256)"](100);
      // owner should now have nothing left to withdraw
      await expect(cellar["withdraw(uint256)"](1)).to.revertedWith(
        "NoNonemptyUserDeposits()"
      );

      // alice only has $100 to withdraw, withdrawing $150 should revert
      await expect(
        cellar.connect(alice)["withdraw(uint256)"](150)
      ).to.be.revertedWith("FailedWithdraw()");
    });
  });

  describe("swap", () => {
    beforeEach(async () => {
      // Mint initial liquidity to cellar
      await usdc.mint(cellar.address, 2000);
    });

    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      await cellar.swap(usdc.address, dai.address, 1000, 950);
      expect(await usdc.balanceOf(cellar.address)).to.eq(1000);
      expect(await dai.balanceOf(cellar.address)).to.be.at.least(950);

      // expect fail if minimum amount of output tokens not received
      await expect(
        cellar.swap(usdc.address, dai.address, 1000, 2000)
      ).to.be.revertedWith("amountOutMin invariant failed");
    });

    it("should revert if trying to swap more tokens than cellar has", async () => {
      await expect(
        cellar.swap(usdc.address, dai.address, 3000, 2800)
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
    });
  });

  describe("multihopSwap", () => {
    beforeEach(async () => {
      // Mint initial liquidity to cellar
      await weth.mint(cellar.address, 2000);
    });

    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      await cellar.multihopSwap(
        [weth.address, usdc.address, dai.address],
        1000,
        950
      );
      expect(await weth.balanceOf(cellar.address)).to.eq(1000);
      expect(await dai.balanceOf(cellar.address)).to.be.at.least(950);

      await expect(
        cellar.multihopSwap(
          [weth.address, usdc.address, dai.address],
          1000,
          2000
        )
      ).to.be.revertedWith("amountOutMin invariant failed");
    });

    it("should revert if trying to swap more tokens than cellar has", async () => {
      await expect(
        cellar.multihopSwap(
          [weth.address, usdc.address, dai.address],
          3000,
          2800
        )
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
    });
  });

  describe("enterStrategy", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](100);

      // alice adds $100 of inactive assets
      await cellar.connect(alice)["deposit(uint256)"](100);

      // set Aave lending pool index to x1.25
      await lendingPool.setLiquidityIndex(
        BigNumber.from("1250000000000000000000000000")
      );

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy(usdc.address, 200);
    });

    it("should deposit cellar inactive assets into Aave", async () => {
      // cellar's initial $200 - deposited $200 = $0
      expect(await usdc.balanceOf(cellar.address)).to.eq(0);
      // aave's initial $5000 + deposited $200 = $5200
      expect(await usdc.balanceOf(aUSDC.address)).to.eq(5200);
    });

    it("should return correct amount of aTokens to cellar", async () => {
      // should mint 160 aUSDC = $200 / x1.25
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(160);
    });
  });

  describe("redeemFromAave", () => {
    beforeEach(async () => {
      // Mint initial liquidity to cellar
      await usdc.mint(cellar.address, 1000);

      await cellar.enterStrategy(usdc.address, 1000);

      await cellar.redeemFromAave(usdc.address, 1000);
    });

    it("should return correct amount of tokens back to cellar from lending pool", async () => {
      expect(await usdc.balanceOf(cellar.address)).to.eq(1000);
    });

    it("should transfer correct amount of aTokens to lending pool", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
    });
  });
});
