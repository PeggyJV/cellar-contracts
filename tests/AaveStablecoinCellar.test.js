const { ethers } = require("hardhat");
const { expect } = require("chai");
const { BigNumber } = require("ethers");

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

describe("AaveStablecoinCellar", () => {
  let owner;
  let alice;
  let cellar;
  let usdc;
  let weth;
  let dai;
  let usdt;
  let router;
  let lendingPool;
  let incentivesController;
  let aUSDC;
  let aDAI;
  let stkAAVE;
  let aave;
  let dataProvider;

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
    usdt = await Token.deploy("USDT");

    await usdc.deployed();
    await dai.deployed();
    await weth.deployed();
    await usdt.deployed();

    // Deploy mock aUSDC
    const MockAToken = await ethers.getContractFactory("MockAToken");
    aUSDC = await MockAToken.deploy(usdc.address, "aUSDC");
    await aUSDC.deployed();
    
    // Deploy mock aDAI
    aDAI = await MockAToken.deploy(dai.address, "aDAI");
    await aDAI.deployed();

    // Deploy mock Aave USDC lending pool
    const LendingPool = await ethers.getContractFactory("MockLendingPool");
    lendingPool = await LendingPool.deploy();
    await lendingPool.deployed();

    await lendingPool.initReserve(usdc.address, aUSDC.address);
    await lendingPool.initReserve(dai.address, aDAI.address);
    
    await aUSDC.setLendingPool(lendingPool.address);
    await aDAI.setLendingPool(lendingPool.address);

    // Deploy mock AAVE
    aave = await Token.deploy("AAVE");

    // Deploy mock stkAAVE
    const MockStkAAVE = await ethers.getContractFactory("MockStkAAVE");
    stkAAVE = await MockStkAAVE.deploy(aave.address);
    await stkAAVE.deployed();

    // Deploy mock Aave incentives controller
    const MockIncentivesController = await ethers.getContractFactory(
      "MockIncentivesController"
    );
    incentivesController = await MockIncentivesController.deploy(
      stkAAVE.address
    );
    await incentivesController.deployed();

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
      incentivesController.address,
      stkAAVE.address,
      aave.address,
      weth.address,
      usdc.address,
      "Sommelier Aave Stablecoin Cellar LP Token",
      "SASCT"
    );
    await cellar.deployed();

    // Mint mock tokens to signers
    await usdc.mint(owner.address, 1000);
    await dai.mint(owner.address, 1000);
    await weth.mint(owner.address, 1000);
    await usdt.mint(owner.address, 1000);

    await usdc.mint(alice.address, 1000);
    await dai.mint(alice.address, 1000);
    await weth.mint(alice.address, 1000);
    await usdt.mint(alice.address, 1000);

    // Approve cellar to spend mock tokens
    await usdc.approve(cellar.address, 1000);
    await dai.approve(cellar.address, 1000);
    await weth.approve(cellar.address, 1000);
    await usdt.approve(cellar.address, 1000);
    
    await usdc.connect(alice).approve(cellar.address, 1000);
    await dai.connect(alice).approve(cellar.address, 1000);
    await weth.connect(alice).approve(cellar.address, 1000);
    await usdt.connect(alice).approve(cellar.address, 1000);

    // Mint initial liquidity to Aave USDC lending pool
    await usdc.mint(aUSDC.address, 5000);

    // Mint initial liquidity to router
    await usdc.mint(router.address, 5000);
    await dai.mint(router.address, 5000);
    await weth.mint(router.address, 5000);
    await usdt.mint(router.address, 5000);

    // Initialize with mock tokens as input tokens
    await cellar.approveInputToken(usdc.address);
    await cellar.approveInputToken(dai.address);
    await cellar.approveInputToken(weth.address);
    await cellar.approveInputToken(usdt.address);
  });

  describe("deposit", () => {
    it("should mint correct amount of shares to user", async () => {
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

    it("should swap input token for current lending token if not already", async () => {
      const initialUserBalance = await dai.balanceOf(owner.address);
      const initialCellarBalance = await usdc.balanceOf(cellar.address);

      await cellar["deposit(address,uint256,uint256,address)"](
        dai.address,
        100,
        95,
        owner.address
      );

      const updatedUserBalance = await dai.balanceOf(owner.address);
      const updatedCellarBalance = await usdc.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner
      expect(updatedUserBalance - initialUserBalance).to.eq(-100);
      // expect $95 to have been received by cellar (simulate $5 being lost during swap)
      expect(updatedCellarBalance - initialCellarBalance).to.eq(95);

      // expect shares to be minted to owner as if they deposited $95 even though
      // they deposited $100 (because that is what the cellar received after swap)
      expect(await cellar.balanceOf(owner.address)).to.eq(95);
    });

    it("should mint shares to receiver instead of caller if specified", async () => {
      // owner mints to alice
      await cellar["deposit(uint256,address)"](100, alice.address);
      // expect alice receives 100 shares
      expect(await cellar.balanceOf(alice.address)).to.eq(100);
      // expect owner receives no shares
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
    });

    it("should emit Deposit event", async () => {
      await expect(cellar["deposit(uint256,address)"](100, alice.address))
        .to.emit(cellar, "Deposit")
        .withArgs(owner.address, alice.address, 100, 100);
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
      await cellar.enterStrategy();

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
      await cellar.enterStrategy();

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

    it("should not allow unapproved 3rd party to withdraw using another's shares", async () => {
      // owner tries to withdraw alice's shares without approval (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          100,
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      cellar.connect(alice).approve(100);

      // owner tries again after alice approved owner to withdraw $100 (expect pass)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          100,
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      // owner tries to withdraw another $100 (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          100,
          owner.address,
          alice.address
        )
      ).to.be.reverted;
    });

    it("should emit Withdraw event", async () => {
      await expect(
        cellar["withdraw(uint256,address,address)"](
          100,
          alice.address,
          owner.address
        )
      )
        .to.emit(cellar, "Withdraw")
        .withArgs(owner.address, alice.address, owner.address, 100, 100);
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

    it("should emit Swapped event", async () => {
      await expect(cellar.swap(usdc.address, dai.address, 1000, 950))
        .to.emit(cellar, "Swapped")
        .withArgs(
          usdc.address,
          1000,
          dai.address,
          950,
          (await timestamp()) + 1
        );
    });
  });

  describe("multihopSwap", () => {
    beforeEach(async () => {
      // Mint initial liquidity to cellar
      await weth.mint(cellar.address, 2000);
    });

    it("should swap input tokens for at least the minimum amount of output tokens", async () => {
      const balanceWETHBefore = await weth.balanceOf(cellar.address);
      const balanceUSDTBefore = await usdt.balanceOf(cellar.address);
      
      await cellar.multihopSwap(
        [weth.address, usdc.address, usdt.address],
        1000,
        950
      );

      expect(balanceUSDTBefore).to.eq(0);
      expect(await weth.balanceOf(cellar.address)).to.eq(balanceWETHBefore - 1000);
      expect(await usdt.balanceOf(cellar.address)).to.eq(balanceUSDTBefore + 950);

      await expect(
        cellar.multihopSwap(
          [weth.address, usdc.address, dai.address],
          1000,
          2000
        )
      ).to.be.revertedWith("amountOutMin invariant failed");
    });

    it("multihop swap with two tokens in the path", async () => {
      const balanceWETHBefore = await weth.balanceOf(cellar.address);
      const balanceDAIBefore = await dai.balanceOf(cellar.address);
      
      await cellar.multihopSwap([weth.address, dai.address], 1000, 950);
      
      expect(await weth.balanceOf(cellar.address)).to.eq(balanceWETHBefore - 1000);
      expect(await dai.balanceOf(cellar.address)).to.be.at.least(balanceDAIBefore + 950);
    });

    it("multihop swap with four tokens in the path", async () => {
      await usdc.mint(cellar.address, 2000);
      
      const balanceUSDCBefore = await usdc.balanceOf(cellar.address);
      const balanceUSDTBefore = await usdt.balanceOf(cellar.address);
      
      await cellar.multihopSwap(
        [usdc.address, weth.address, dai.address, usdt.address],
        1000,
        950
      );
      expect(await usdc.balanceOf(cellar.address)).to.eq(balanceUSDCBefore - 1000);
      expect(await usdt.balanceOf(cellar.address)).to.be.at.least(balanceUSDTBefore + 950);
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

    it("should emit Swapped event", async () => {
      await expect(
        cellar.multihopSwap(
          [weth.address, usdc.address, dai.address],
          1000,
          950
        )
      )
        .to.emit(cellar, "Swapped")
        .withArgs(
          weth.address,
          1000,
          dai.address,
          950,
          (await timestamp()) + 1
        );
    });
  });

  describe("enterStrategy", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](100);

      // alice adds $100 of inactive assets
      await cellar.connect(alice)["deposit(uint256)"](100);

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();
    });

    it("should deposit cellar inactive assets into Aave", async () => {
      // cellar's initial $200 - deposited $200 = $0
      expect(await usdc.balanceOf(cellar.address)).to.eq(0);
      // aave's initial $5000 + deposited $200 = $5200
      expect(await usdc.balanceOf(aUSDC.address)).to.eq(5200);
    });

    it("should return correct amount of aTokens to cellar", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(200);
    });

    it("should not allow deposit if cellar does not have enough liquidity", async () => {
      // cellar tries to enter strategy with $100 it does not have
      await expect(cellar.enterStrategy()).to.be.reverted;
    });

    it("should emit DepositToAave event", async () => {
      await cellar["deposit(uint256)"](200);

      await expect(cellar.enterStrategy())
        .to.emit(cellar, "DepositToAave")
        .withArgs(usdc.address, 200, (await timestamp()) + 1);
    });
  });

  describe("claimAndUnstake", () => {
    beforeEach(async () => {
      // simulate cellar contract having 100 stkAAVE to claim
      await incentivesController.addRewards(cellar.address, 100);

      await cellar["claimAndUnstake()"]();
    });

    it("should claim rewards from Aave and begin unstaking", async () => {
      // expect cellar to claim all 100 stkAAVE
      expect(await stkAAVE.balanceOf(cellar.address)).to.eq(100);
    });

    it("should have started 10 day unstaking cooldown period", async () => {
      expect(await stkAAVE.stakersCooldowns(cellar.address)).to.eq(
        await timestamp()
      );
    });
  });

  describe("reinvest", () => {
    beforeEach(async () => {
      await incentivesController.addRewards(cellar.address, 100);
      // cellar claims rewards and begins the 10 day cooldown period
      await cellar["claimAndUnstake()"]();

      await timetravel(864000);

      await cellar["reinvest(uint256)"](95);
    });

    it("should reinvested rewards back into principal", async () => {
      expect(await stkAAVE.balanceOf(cellar.address)).to.eq(0);
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(95);
    });
  });

  describe("redeemFromAave", () => {
    beforeEach(async () => {
      // Mint initial liquidity to cellar
      await usdc.mint(cellar.address, 1000);

      await cellar.enterStrategy();

      await cellar.redeemFromAave(usdc.address, 1000);
    });

    it("should return correct amount of tokens back to cellar from lending pool", async () => {
      expect(await usdc.balanceOf(cellar.address)).to.eq(1000);
    });

    it("should transfer correct amount of aTokens to lending pool", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
    });

    it("should not allow redeeming more than cellar deposited", async () => {
      // cellar tries to redeem $100 when it should have deposit balance of $0
      await expect(cellar.redeemFromAave(usdc.address, 100)).to.be.reverted;
    });

    it("should emit RedeemFromAave event", async () => {
      await usdc.mint(cellar.address, 1000);
      await cellar.enterStrategy();

      await expect(cellar.redeemFromAave(usdc.address, 1000))
        .to.emit(cellar, "RedeemFromAave")
        .withArgs(usdc.address, 1000, (await timestamp()) + 1);
    });
  });

  describe("rebalance", () => {
    beforeEach(async () => {
      await usdc.mint(cellar.address, 1000);
      await cellar.enterStrategy();
    });
    
    it("should rebalance all usdc liquidity in dai", async () => {
      expect(await dai.balanceOf(cellar.address)).to.eq(0);
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(1000);
      
      await cellar.rebalance(dai.address, 0);
      
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
      // After the swap,  amount of  coin will change from the exchange rate of 0.95
      expect(await aDAI.balanceOf(cellar.address)).to.eq(950);
      
      await cellar.redeemFromAave(dai.address, 950)
      
      expect(await aDAI.balanceOf(cellar.address)).to.eq(0);
      expect(await dai.balanceOf(cellar.address)).to.eq(950);
    });

    it("should not be possible to rebalance to the same token", async () => {
      await expect(cellar.rebalance(usdc.address, 0)).to.be.revertedWith(
        "SameLendingToken"
      );
    });
  });
});
