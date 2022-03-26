const { ethers } = require("hardhat");
const { expect } = require("chai");

const Num = (number, decimals) => {
  const [characteristic, mantissa] = number.toString().split(".");
  const padding = mantissa ? decimals - mantissa.length : decimals;
  return characteristic + (mantissa ?? "") + "0".repeat(padding);
};

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

// TODO:
// - test transferring active vs inactive shares
// - test withdrawing another's shares with and without approval

describe("AaveV2StablecoinCellar", () => {
  let owner;
  let alice;
  let bob;
  let cellar;
  let Token;
  let USDC;
  let WETH;
  let DAI;
  let USDT;
  let router;
  let lendingPool;
  let incentivesController;
  let gravity;
  let aUSDC;
  let aDAI;
  let aUSDT;
  let stkAAVE;
  let AAVE;

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    // Deploy mock Uniswap router contract
    const SwapRouter = await ethers.getContractFactory("MockSwapRouter");
    router = await SwapRouter.deploy();
    await router.deployed();

    // Deploy mock tokens
    Token = await ethers.getContractFactory("MockToken");
    USDC = await Token.deploy("USDC", 6);
    DAI = await Token.deploy("DAI", 18);
    WETH = await Token.deploy("WETH", 18);
    USDT = await Token.deploy("USDT", 6);

    await USDC.deployed();
    await DAI.deployed();
    await WETH.deployed();
    await USDT.deployed();

    // Deploy mock aUSDC
    const MockAToken = await ethers.getContractFactory("MockAToken");
    aUSDC = await MockAToken.deploy(USDC.address, "aUSDC");
    await aUSDC.deployed();

    // Deploy mock aDAI
    aDAI = await MockAToken.deploy(DAI.address, "aDAI");
    await aDAI.deployed();

    // Deploy mock aUSDT
    aUSDT = await MockAToken.deploy(USDT.address, "aUSDT");
    await aUSDT.deployed();

    // Deploy mock Aave USDC lending pool
    const LendingPool = await ethers.getContractFactory("MockLendingPool");
    lendingPool = await LendingPool.deploy();
    await lendingPool.deployed();

    await lendingPool.initReserve(USDC.address, aUSDC.address);
    await lendingPool.initReserve(DAI.address, aDAI.address);
    await lendingPool.initReserve(USDT.address, aUSDT.address);

    await aUSDC.setLendingPool(lendingPool.address);
    await aDAI.setLendingPool(lendingPool.address);
    await aUSDT.setLendingPool(lendingPool.address);

    // Deploy mock AAVE
    AAVE = await Token.deploy("AAVE", 18);

    // Deploy mock stkAAVE
    const MockStkAAVE = await ethers.getContractFactory("MockStkAAVE");
    stkAAVE = await MockStkAAVE.deploy(AAVE.address);
    await stkAAVE.deployed();

    // Deploy mock Aave incentives controller
    const MockIncentivesController = await ethers.getContractFactory(
      "MockIncentivesController"
    );
    incentivesController = await MockIncentivesController.deploy(
      stkAAVE.address
    );
    await incentivesController.deployed();

    const MockGravity = await ethers.getContractFactory("MockGravity");
    gravity = await MockGravity.deploy();
    await gravity.deployed();

    // Deploy cellar contract
    const AaveV2StablecoinCellar = await ethers.getContractFactory(
      "AaveV2StablecoinCellar"
    );
    cellar = await AaveV2StablecoinCellar.deploy(
      USDC.address,
      router.address,
      router.address,
      lendingPool.address,
      incentivesController.address,
      gravity.address,
      stkAAVE.address,
      AAVE.address
    );
    await cellar.deployed();

    // Mint mock tokens to signers
    await USDC.mint(owner.address, Num(1000, 6));
    await DAI.mint(owner.address, Num(1000, 18));
    await WETH.mint(owner.address, Num(1000, 18));
    await USDT.mint(owner.address, Num(1000, 6));

    await USDC.mint(alice.address, Num(1000, 6));
    await DAI.mint(alice.address, Num(1000, 18));
    await WETH.mint(alice.address, Num(1000, 18));
    await USDT.mint(alice.address, Num(1000, 6));

    // Approve cellar to spend mock tokens
    await USDC.approve(cellar.address, ethers.constants.MaxUint256);
    await DAI.approve(cellar.address, ethers.constants.MaxUint256);
    await WETH.approve(cellar.address, ethers.constants.MaxUint256);
    await USDT.approve(cellar.address, ethers.constants.MaxUint256);

    await USDC.connect(alice).approve(
      cellar.address,
      ethers.constants.MaxUint256
    );
    await DAI.connect(alice).approve(
      cellar.address,
      ethers.constants.MaxUint256
    );
    await WETH.connect(alice).approve(
      cellar.address,
      ethers.constants.MaxUint256
    );
    await USDT.connect(alice).approve(
      cellar.address,
      ethers.constants.MaxUint256
    );

    // Approve cellar to spend shares (to take as fees)
    await cellar.approve(cellar.address, ethers.constants.MaxUint256);

    await cellar
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);

    // Mint initial liquidity to Aave USDC lending pool
    await USDC.mint(aUSDC.address, Num(5000, 6));

    // Mint initial liquidity to router
    await USDC.mint(router.address, Num(5000, 6));
    await DAI.mint(router.address, Num(5000, 18));
    await WETH.mint(router.address, Num(5000, 18));
    await USDT.mint(router.address, Num(5000, 6));
  });

  describe("deposit", () => {
    it("should mint correct amount of shares to user", async () => {
      // add $100 of inactive assets in cellar
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      // expect 100 shares to be minted (because total supply of shares is 0)
      expect(await cellar.balanceOf(owner.address)).to.eq(Num(100, 18));

      // add $100 to inactive assets (w/o minting shares)
      await USDC.mint(cellar.address, Num(100, 6));

      // add $50 of inactive assets in cellar
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(50, 6), alice.address);
      // expect 25 shares = 100 total shares * ($50 / $200) to be minted
      expect(await cellar.balanceOf(alice.address)).to.eq(Num(25, 18));
    });

    it("should transfer input token from user to cellar", async () => {
      const ownerOldBalance = await USDC.balanceOf(owner.address);
      const cellarOldBalance = await USDC.balanceOf(cellar.address);

      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      const ownerNewBalance = await USDC.balanceOf(owner.address);
      const cellarNewBalance = await USDC.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner to cellar
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(
        Num(-100, 6)
      );
      expect((cellarNewBalance - cellarOldBalance).toString()).to.eq(
        Num(100, 6)
      );
    });

    it("should mint shares to receiver instead of caller if specified", async () => {
      // owner mints to alice
      await cellar["deposit(uint256,address)"](Num(100, 6), alice.address);
      // expect alice receives 100 shares
      expect(await cellar.balanceOf(alice.address)).to.eq(Num(100, 18));
      // expect owner receives no shares
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
    });

    it("should deposit all user's balance if they try depositing more than their balance", async () => {
      // owner has $1000 to deposit, withdrawing $5000 should only withdraw $1000
      await cellar["deposit(uint256,address)"](Num(5000, 6), owner.address);
      expect(await USDC.balanceOf(owner.address)).to.eq(0);
      expect(await USDC.balanceOf(cellar.address)).to.eq(Num(1000, 6));
    });

    it("should use and store index of first non-zero deposit", async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      // owner withdraws everything from deposit object at index 0
      await cellar["withdraw(uint256,address,address)"](
        Num(100, 6),
        owner.address,
        owner.address
      );
      // expect next non-zero deposit is set to index 1
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(1);

      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);
      // alice only withdraws half from index 0, leaving some shares remaining
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(50, 6),
          alice.address,
          alice.address
        );
      // expect next non-zero deposit is set to index 0 since some shares still remain
      expect(await cellar.currentDepositIndex(alice.address)).to.eq(0);
    });

    it("should not allow deposits of 0", async () => {
      await expect(
        cellar["deposit(uint256,address)"](0, owner.address)
      ).to.be.revertedWith("ZeroAssets()");
    });

    it("should emit Deposit event", async () => {
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(1000, 6), alice.address);

      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      await expect(
        cellar["deposit(uint256,address)"](Num(2000, 6), alice.address)
      )
        .to.emit(cellar, "Deposit")
        .withArgs(
          owner.address,
          alice.address,
          USDC.address,
          Num(1000, 6),
          Num(800, 18)
        );
    });
  });

  describe("withdraw", () => {
    beforeEach(async () => {
      // both owner and alice should start off owning 50% of the cellar's total assets each
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);
    });

    it("should withdraw correctly when called with all inactive shares", async () => {
      const ownerOldBalance = await USDC.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $100 (50% of total)
      await cellar["withdraw(uint256,address,address)"](
        Num(100, 6),
        owner.address,
        owner.address
      );
      const ownerNewBalance = await USDC.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(Num(100, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await USDC.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $100 (50% of total)
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(100, 6),
          alice.address,
          alice.address
        );
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(100, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with all active shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      // mimic growth from $200 -> $250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      const ownerOldBalance = await USDC.balanceOf(owner.address);
      await cellar["withdraw(uint256,address,address)"](
        Num(125, 6),
        owner.address,
        owner.address
      );
      const ownerNewBalance = await USDC.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $125 (50% of total)
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(Num(125, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await USDC.balanceOf(alice.address);
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(125, 6),
          alice.address,
          alice.address
        );
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $125 (50% of total)
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(125, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with active and inactive shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      // mimic growth from $200 -> $250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      // owner adds $100 of inactive assets
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      // alice adds $75 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(75, 6), alice.address);

      const ownerOldBalance = await USDC.balanceOf(owner.address);
      await cellar["withdraw(uint256,address,address)"](
        Num(225, 6),
        owner.address,
        owner.address
      );
      const ownerNewBalance = await USDC.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(
        Num(100 + 125, 6)
      );
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await USDC.balanceOf(alice.address);
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(200, 6),
          alice.address,
          alice.address
        );
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(
        Num(75 + 125, 6)
      );
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw all user's assets if they try withdrawing more than their balance", async () => {
      await cellar["withdraw(uint256,address,address)"](
        Num(100, 6),
        owner.address,
        owner.address
      );
      // owner should now have nothing left to withdraw
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
      await expect(
        cellar["withdraw(uint256,address,address)"](
          1,
          owner.address,
          owner.address
        )
      ).to.be.revertedWith("ZeroShares()");

      // alice only has $100 to withdraw, withdrawing $150 should only withdraw $100
      const aliceOldBalance = await USDC.balanceOf(alice.address);
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(150, 6),
          alice.address,
          alice.address
        );
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(100, 6));
    });

    it("should not allow withdraws of 0", async () => {
      await expect(
        cellar["withdraw(uint256,address,address)"](
          0,
          owner.address,
          owner.address
        )
      ).to.be.revertedWith("ZeroAssets()");
    });

    it("should not allow unapproved account to withdraw using another's shares", async () => {
      // owner tries to withdraw alice's shares without approval (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(1, 6),
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      cellar.connect(alice).approve(Num(1, 6));

      // owner tries again after alice approved owner to withdraw $1 (expect pass)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(1, 6),
          owner.address,
          alice.address
        )
      ).to.be.reverted;

      // owner tries to withdraw another $1 (expect revert)
      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(1, 6),
          owner.address,
          alice.address
        )
      ).to.be.reverted;
    });

    it("should only withdraw from strategy if holding pool does not contain enough funds", async () => {
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(125, 6), alice.address);

      const beforeActiveAssets = await cellar.activeAssets();

      // with $125 in strategy and $125 in holding pool, should with
      await cellar["withdraw(uint256,address,address)"](
        Num(125, 6),
        owner.address,
        owner.address
      );

      const afterActiveAssets = await cellar.activeAssets();

      // active assets from strategy should not have changed
      expect(afterActiveAssets).to.eq(beforeActiveAssets);
      // should have withdrawn from holding pool funds
      expect(await cellar.inactiveAssets()).to.eq(0);
    });

    it("should emit Withdraw event", async () => {
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      await expect(
        cellar["withdraw(uint256,address,address)"](
          Num(2000, 6),
          alice.address,
          owner.address
        )
      )
        .to.emit(cellar, "Withdraw")
        .withArgs(
          alice.address,
          owner.address,
          USDC.address,
          Num(125, 6),
          Num(100, 18)
        );
    });
  });

  describe("transfer", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
    });

    it("should correctly update deposit accounting upon transferring shares", async () => {
      const depositTimestamp = await timestamp();

      const aliceOldBalance = await cellar.balanceOf(alice.address);
      await cellar.transfer(alice.address, Num(25, 18));
      const aliceNewBalance = await cellar.balanceOf(alice.address);

      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(25, 18));

      const ownerDeposit = await cellar.userDeposits(owner.address, 0);
      const aliceDeposit = await cellar.userDeposits(alice.address, 0);

      expect(ownerDeposit[0]).to.eq(Num(75, 18)); // expect 75 assets
      expect(ownerDeposit[1]).to.eq(Num(75, 18)); // expect 75 shares
      expect(ownerDeposit[2]).to.eq(depositTimestamp);
      expect(aliceDeposit[0]).to.eq(Num(25, 18)); // expect 25 assets
      expect(aliceDeposit[1]).to.eq(Num(25, 18)); // expect 25 shares
      expect(aliceDeposit[2]).to.eq(depositTimestamp);
    });

    it("should correctly withdraw transferred shares", async () => {
      // active $100 worth of active shares -> $125
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      // gain $100 worth of inactive shares
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      // transfer all shares to alice
      await cellar.transfer(
        alice.address,
        await cellar.balanceOf(owner.address)
      );

      const aliceOldBalance = await USDC.balanceOf(alice.address);

      // alice redeem all the shares that have been transferred to her and withdraw all of her assets
      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          await cellar.convertToAssets(await cellar.balanceOf(alice.address)),
          alice.address,
          alice.address
        );

      const aliceNewBalance = await USDC.balanceOf(alice.address);

      // expect alice to have redeemed all the shares transferred to her for $225 in assets
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(
        Num(125 + 100, 6)
      );
    });

    it("should only transfer active shares if specified", async () => {
      // active $100 worth of shares
      await cellar.enterStrategy();
      const expectedShares = await cellar.balanceOf(owner.address);

      // gain $100 worth of inactive shares
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      const aliceOldBalance = await cellar.balanceOf(alice.address);

      // attempting to transfer all active shares should transfer $100 worth of active shares (and not the
      // $100 worth of inactive shares) and not revert
      await cellar["transferFrom(address,address,uint256,bool)"](
        owner.address,
        alice.address,
        await cellar.balanceOf(owner.address),
        true
      );

      const aliceNewBalance = await cellar.balanceOf(alice.address);

      // expect alice to have received $100 worth of shares
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(
        expectedShares
      );
    });

    it("should use and store index of first non-zero deposit", async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      // owner transfers everything from deposit object at index 0
      await cellar.transfer(alice.address, Num(100, 18));
      // expect next non-zero deposit is set to index 1
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(1);

      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);
      // alice only transfers half from index 0, leaving some shares remaining
      await cellar.connect(alice).transfer(owner.address, Num(50, 18));
      // expect next non-zero deposit is set to index 0 since some shares still remain
      expect(await cellar.currentDepositIndex(alice.address)).to.eq(0);
    });

    it("should require approval for transferring other's shares", async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      await cellar.approve(alice.address, Num(50, 18));

      await cellar
        .connect(alice)
        ["transferFrom(address,address,uint256)"](
          owner.address,
          alice.address,
          Num(50, 18)
        );

      await expect(
        cellar["transferFrom(address,address,uint256)"](
          alice.address,
          owner.address,
          Num(200, 18)
        )
      ).to.be.reverted;
    });
  });

  describe("enterStrategy", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);

      // alice adds $100 of inactive assets
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();
    });

    it("should deposit cellar inactive assets into Aave", async () => {
      // cellar's initial $200 - deposited $200 = $0
      expect(await USDC.balanceOf(cellar.address)).to.eq(0);
      // aave's initial $5000 + deposited $200 = $5200
      expect(await USDC.balanceOf(aUSDC.address)).to.eq(Num(5200, 6));
    });

    it("should return correct amount of aTokens to cellar", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(Num(200, 6));
    });

    it("should not allow deposit if cellar does not have enough liquidity", async () => {
      // cellar tries to enter strategy with $100 it does not have
      await expect(cellar.enterStrategy()).to.be.reverted;
    });

    it("should emit DepositToAave event", async () => {
      await cellar["deposit(uint256,address)"](Num(200, 6), owner.address);

      await expect(cellar.enterStrategy())
        .to.emit(cellar, "DepositToAave")
        .withArgs(USDC.address, Num(200, 6));
    });
  });

  describe("claimAndUnstake", () => {
    beforeEach(async () => {
      // simulate cellar contract having 100 stkAAVE to claim
      await incentivesController.addRewards(cellar.address, Num(100, 18));

      await cellar["claimAndUnstake()"]();
    });

    it("should claim rewards from Aave and begin unstaking", async () => {
      // expect cellar to claim all 100 stkAAVE
      expect(await stkAAVE.balanceOf(cellar.address)).to.eq(Num(100, 18));
    });

    it("should have started 10 day unstaking cooldown period", async () => {
      expect(await stkAAVE.stakersCooldowns(cellar.address)).to.eq(
        await timestamp()
      );
    });
  });

  describe("reinvest", () => {
    beforeEach(async () => {
      await incentivesController.addRewards(cellar.address, Num(100, 18));
      // cellar claims rewards and begins the 10 day cooldown period
      await cellar["claimAndUnstake()"]();

      await timetravel(864000);

      await cellar.reinvest([AAVE.address, WETH.address, USDC.address], 0);
    });

    it("should reinvested rewards back into principal", async () => {
      expect(await stkAAVE.balanceOf(cellar.address)).to.eq(0);
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(Num(95, 6));
    });

    it("should have accrued performance fees", async () => {
      const accruedPerformanceFees = (await cellar.feesData())[4];

      // expect $4.75 ($95 * 0.05 = $4.75) worth of fees to be minted as shares
      expect(await cellar.balanceOf(cellar.address)).to.eq(Num(4.75, 18));
      expect(accruedPerformanceFees).to.eq(Num(4.75, 18));
    });

    it("should revert with an invalid swap path", async () => {
      await expect(
        cellar.reinvest([WETH.address, USDC.address, AAVE.address], 0)
      ).to.be.revertedWith(
        `InvalidSwapPath(["${WETH.address}", "${USDC.address}", "${AAVE.address}"])`
      );
    });
  });

  describe("rebalance", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);
      await cellar.enterStrategy();
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(500, 6), owner.address);

      // set initial fee data
      await cellar.accrueFees();
    });

    it("should rebalance all USDC liquidity into DAI", async () => {
      expect(await DAI.balanceOf(cellar.address)).to.eq(0);
      expect(await cellar.totalAssets()).to.eq(Num(1500, 6));

      await cellar.rebalance([USDC.address, DAI.address], 0);

      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
      expect(await aDAI.balanceOf(cellar.address)).to.be.at.least(Num(950, 18));
    });

    it("should use a multihop swap when needed", async () => {
      await cellar.rebalance([USDC.address, DAI.address, USDT.address], 0);
    });

    it("should not be possible to rebalance to the same token", async () => {
      const asset = await cellar.asset();
      await expect(
        cellar.rebalance([USDC.address, asset], Num(950, 18))
      ).to.be.revertedWith(`SameAsset("${asset}")`);
    });

    it("should only be able to rebalance from the current asset", async () => {
      await expect(
        cellar.rebalance([DAI.address, USDT.address], Num(950, 18))
      ).to.be.revertedWith(
        `InvalidSwapPath(["${DAI.address}", "${USDT.address}"])`
      );
    });

    it("should have accrued performance fees", async () => {
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      const accruedPerformanceFeesBefore = (await cellar.feesData())[4];
      const feesBefore = await cellar.balanceOf(cellar.address);

      await cellar.rebalance([USDC.address, DAI.address], Num(950, 18));

      const accruedPerformanceFeesAfter = (await cellar.feesData())[4];
      const feesAfter = await cellar.balanceOf(cellar.address);

      expect(accruedPerformanceFeesAfter.gt(accruedPerformanceFeesBefore)).to.be
        .true;
      expect(feesAfter.gt(feesBefore)).to.be.true;
    });
  });

  describe("accrueFees", () => {
    it("should accrue platform fees", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await timetravel(86400); // 1 day

      await cellar.accrueFees();

      const accruedPlatformFees = (await cellar.feesData())[3];
      const feesInAssets = await cellar.convertToAssets(accruedPlatformFees);

      // ~$0.027 worth of shares in fees = $1000 * 86400 sec * (1% / secsPerYear)
      expect(feesInAssets).to.be.closeTo(Num(0.027, 6), Num(0.001, 6));
    });

    it("should accrue performance fees", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await cellar.accrueFees();

      // mimic growth from $1000 -> $1250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      await cellar.accrueFees();

      const performanceFees = (await cellar.feesData())[4];
      // expect cellar to have received $12.5 fees in shares = $250 gain * 5%,
      // which would be ~10 shares at the time of accrual
      expect(performanceFees).to.be.closeTo(Num(10, 18), Num(0.001, 18));

      const ownerAssetBalance = await cellar.convertToAssets(
        await cellar.balanceOf(owner.address)
      );
      const cellarAssetBalance = await cellar.convertToAssets(
        await cellar.balanceOf(cellar.address)
      );

      // expect to be ~$1250 (will be off by an extremely slight amount due to
      // converToAssets truncating 18 decimals of precision to 6 decimals)
      expect(
        ethers.BigNumber.from(ownerAssetBalance).add(
          ethers.BigNumber.from(cellarAssetBalance)
        )
      ).to.be.closeTo(Num(1250, 6), Num(0.001, 6));
    });

    it("should burn performance fees as insurance for negative performance", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await cellar.accrueFees();

      // mimic growth from $1000 -> $1250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      await cellar.accrueFees();

      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1000000000000000000000000000")
      );

      await cellar.accrueFees();

      const performanceFees = (await cellar.feesData())[4];

      // expect all performance fee shares to have been burned
      expect(performanceFees).to.eq(0);
    });

    it("should be able to transfer fees to Cosmos", async () => {
      // accrue some platform fees
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);
      await cellar.enterStrategy();
      await timetravel(86400); // 1 day
      await cellar.accrueFees();

      // accrue some performance fees
      await lendingPool.setLiquidityIndex(Num(1.25, 27));
      await cellar.accrueFees();

      const fees = await cellar.balanceOf(cellar.address);
      const accruedPlatformFees = (await cellar.feesData())[3];
      const accruedPerformanceFees = (await cellar.feesData())[4];
      expect(fees).to.eq(accruedPlatformFees.add(accruedPerformanceFees));

      const feeInAssets = await cellar.convertToAssets(fees);

      await cellar.transferFees();

      // expect all fee shares to be transferred out
      expect(await cellar.balanceOf(cellar.address)).to.eq(0);
      expect(await USDC.balanceOf(gravity.address)).to.eq(feeInAssets);
    });

    it("should only withdraw from strategy if holding pool does not contain enough funds", async () => {
      // accrue some platform fees
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);
      await cellar.enterStrategy();
      await timetravel(86400); // 1 day
      await cellar.accrueFees();

      // accrue some performance fees
      await lendingPool.setLiquidityIndex(Num(1.25, 27));
      await cellar.accrueFees();

      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);

      const beforeActiveAssets = await cellar.activeAssets();
      const beforeInactiveAssets = await cellar.inactiveAssets();

      // redeems fee shares for their underlying assets and sends them to Cosmos
      await cellar.transferFees();

      const afterActiveAssets = await cellar.activeAssets();
      const afterInactiveAssets = await cellar.inactiveAssets();

      // active assets from strategy should not have changed
      expect(afterActiveAssets).to.eq(beforeActiveAssets);
      // should have withdrawn from holding pool funds
      expect(afterInactiveAssets.lt(beforeInactiveAssets)).to.be.true;
    });
  });

  describe("pause", () => {
    it("should prevent users from depositing while paused", async () => {
      await cellar.setPause(true);
      expect(
        cellar["deposit(uint256,address)"](Num(100, 6), owner.address)
      ).to.be.revertedWith("ContractPaused()");
    });

    it("should emits a Pause event", async () => {
      await expect(cellar.setPause(true))
        .to.emit(cellar, "Pause")
        .withArgs(true);
    });
  });

  describe("shutdown", () => {
    it("should prevent users from depositing while shutdown", async () => {
      await cellar["deposit(uint256,address)"](Num(100, 6), owner.address);
      await cellar.shutdown();
      expect(
        cellar["deposit(uint256,address)"](Num(100, 6), owner.address)
      ).to.be.revertedWith("ContractShutdown()");
    });

    it("should allow users to withdraw", async () => {
      // alice first deposits
      await cellar
        .connect(alice)
        ["deposit(uint256,address)"](Num(100, 6), alice.address);

      // cellar is shutdown
      await cellar.shutdown();

      await cellar
        .connect(alice)
        ["withdraw(uint256,address,address)"](
          Num(100, 6),
          alice.address,
          alice.address
        );
    });

    it("should withdraw all active assets from Aave", async () => {
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);

      await cellar.enterStrategy();

      // mimic growth from $1000 -> $1250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      await cellar.shutdown();

      // expect all of active liquidity to be withdrawn from Aave
      expect(await USDC.balanceOf(cellar.address)).to.eq(Num(1250, 6));

      // should allow users to withdraw from holding pool
      await cellar["withdraw(uint256,address,address)"](
        Num(1250, 6),
        owner.address,
        owner.address
      );
    });

    it("should emit a Shutdown event", async () => {
      await expect(cellar.shutdown()).to.emit(cellar, "Shutdown");
    });
  });

  describe("restrictLiquidity", () => {
    it("should prevent deposit if greater than max liquidity", async () => {
      // mint $5m to cellar (to hit liquidity cap)
      await USDC.mint(cellar.address, Num(5_000_000, 6));

      await expect(
        cellar["deposit(uint256,address)"](1, owner.address)
      ).to.be.revertedWith(`LiquidityRestricted(${Num(5_000_000, 6)})`);
    });

    it("should prevent deposit if greater than max deposit", async () => {
      await USDC.mint(owner.address, Num(50_001, 6));
      await expect(
        cellar["deposit(uint256,address)"](Num(50_001, 6), owner.address)
      ).to.be.revertedWith(`DepositRestricted(${Num(50_000, 6)})`);

      await cellar["deposit(uint256,address)"](Num(50_000, 6), owner.address);
      await expect(
        cellar["deposit(uint256,address)"](1, owner.address)
      ).to.be.revertedWith(`DepositRestricted(${Num(50_000, 6)})`);
    });

    it("should allow deposits above max deposit and max liquidity once restriction removed", async () => {
      // mint $5m to cellar (to hit liquidity cap)
      await USDC.mint(cellar.address, Num(5_000_000, 6));

      await cellar.removeLiquidityRestriction();

      // should be able to depositing past the max deposit restriction since its been removed
      await cellar["deposit(uint256,address)"](Num(50_001, 6), owner.address);
    });
  });

  describe("sweep", () => {
    let SOMM;

    beforeEach(async () => {
      SOMM = await Token.deploy("SOMM", 18);
      await SOMM.deployed();

      // mimic 1000 SOMM being transferred to the cellar contract by accident
      await SOMM.mint(cellar.address, 1000);
    });

    it("should not allow assets managed by cellar to be transferred out", async () => {
      await expect(cellar.sweep(USDC.address)).to.be.revertedWith(
        `ProtectedAsset("${USDC.address}")`
      );
      await expect(cellar.sweep(aUSDC.address)).to.be.revertedWith(
        `ProtectedAsset("${aUSDC.address}")`
      );
      await expect(cellar.sweep(cellar.address)).to.be.revertedWith(
        `ProtectedAsset("${cellar.address}")`
      );
    });

    it("should recover tokens accidentally transferred to the contract", async () => {
      await cellar.sweep(SOMM.address);

      // expect 1000 SOMM to have been transferred from cellar to owner
      expect(await SOMM.balanceOf(owner.address)).to.eq(1000);
      expect(await SOMM.balanceOf(cellar.address)).to.eq(0);
    });

    it("should emit Sweep event", async () => {
      await expect(cellar.sweep(SOMM.address))
        .to.emit(cellar, "Sweep")
        .withArgs(SOMM.address, 1000);
    });
  });

  describe("accounting", () => {
    let activeShares;
    let activeAssets;
    let inactiveShares;
    let inactiveAssets;

    beforeEach(async () => {
      // Start with some liquidity in the cellar to mimic more realistic conditions
      await USDC.mint(bob.address, Num(1_000_000, 6));
      await USDC.connect(bob).approve(
        cellar.address,
        ethers.constants.MaxUint256
      );

      await cellar.removeLiquidityRestriction();

      await cellar
        .connect(bob)
        ["deposit(uint256,address)"](Num(10_000, 6), bob.address);
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(Num(1.25, 27));

      activeShares = await cellar.balanceOf(bob.address);
      activeAssets = Num(10_000 * 1.25, 6);

      await cellar
        .connect(bob)
        ["deposit(uint256,address)"](Num(42_069, 6), bob.address);

      inactiveShares = (await cellar.balanceOf(bob.address)).sub(activeShares);
      inactiveAssets = Num(42_069, 6);
    });

    it("should accurately convert shares to assets and vice versa", async () => {
      // has been tested successfully from 0 up to 10_000, but set to run once to avoid long test time
      for (let i = 0; i < 1; i++) {
        const initialAssets = Num(i, 6);
        const assetsToShares = await cellar.convertToShares(initialAssets);
        const sharesBackToAssets = await cellar.convertToAssets(assetsToShares);
        expect(sharesBackToAssets).to.eq(initialAssets);
        const assetsBackToShares = await cellar.convertToShares(
          sharesBackToAssets
        );
        expect(assetsBackToShares).to.eq(assetsToShares);
      }
    });

    it("should correctly preview deposits", async () => {
      // set to run only only once, but successfully from 1 to 1000 (max amount redeemable)
      for (let i = 1000; i <= 1000; i++) {
        const assets = Num(i, 6);

        const expectedShares = await cellar.previewDeposit(assets);
        const mintedShares = await cellar.callStatic[
          "deposit(uint256,address)"
        ](assets, owner.address);

        expect(expectedShares).to.eq(mintedShares);
      }
    });

    it("should correctly preview mint", async () => {
      await USDC.mint(owner.address, Num(1_000_000, 6));

      // set to run only only once, but successfully from 1 to 1000 (max amount redeemable)
      for (let i = 1000; i <= 1000; i++) {
        const shares = Num(i, 18);

        const expectedAssets = await cellar.previewMint(shares);
        const depositedAssets = await cellar.callStatic[
          "mint(uint256,address)"
        ](shares, owner.address);

        expect(depositedAssets).to.eq(expectedAssets);
      }
    });

    it("should correctly preview withdraws", async () => {
      await cellar["deposit(uint256,address)"](Num(1000, 6), owner.address);
      await cellar.enterStrategy();

      // set to run only only once, but successfully from 1 to 1000 (max amount withdrawable)
      for (let i = 1000; i <= 1000; i++) {
        const assets = Num(i, 6);

        const expectedShares = await cellar.previewWithdraw(assets);
        const redeemedShares = await cellar.callStatic[
          "withdraw(uint256,address,address)"
        ](assets, owner.address, owner.address);

        expect(redeemedShares).to.eq(expectedShares);
      }
    });

    it("should correctly preview redeems", async () => {
      await USDC.mint(owner.address, Num(1_000_000, 6));
      await cellar["mint(uint256,address)"](Num(1000, 18), owner.address);
      await cellar.enterStrategy();

      // set to run only only once, but successfully from 1 to 1000 (max amount redeemable)
      for (let i = 1000; i <= 1000; i++) {
        const shares = Num(i, 18);

        const expectedAssets = await cellar.previewRedeem(shares);
        const withdrawnAssets = await cellar.callStatic[
          "redeem(uint256,address,address)"
        ](shares, owner.address, owner.address);

        expect(withdrawnAssets).to.eq(expectedAssets);
      }
    });

    it("should accurately retrieve information on a user's deposit balances", async () => {
      const data = await cellar.depositBalances(bob.address);

      expect(data[0].toString()).to.eq(activeShares);
      expect(data[1].toString()).to.eq(inactiveShares);
      expect(data[2].toString()).to.eq(activeAssets);
      expect(data[3].toString()).to.eq(inactiveAssets);
    });
  });

  describe("max", () => {
    it("should correctly find max deposit amount", async () => {
      await cellar.setPause(true);
      expect(await cellar.maxDeposit(owner.address)).to.eq(0);
      await cellar.setPause(false);

      const maxDeposit = Num(50_000, 6);
      expect(await cellar.maxDeposit(owner.address)).to.eq(maxDeposit);
      await USDC.mint(owner.address, maxDeposit);
      await cellar["deposit(uint256,address)"](maxDeposit, owner.address);
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(Num(1.25, 27));
      expect(await cellar.maxDeposit(owner.address)).to.eq(0);

      await cellar.removeLiquidityRestriction();

      expect(await cellar.maxDeposit(owner.address)).to.eq(
        ethers.constants.MaxUint256
      );
    });

    it("should correctly find max mint amount", async () => {
      await cellar.setPause(true);
      expect(await cellar.maxMint(owner.address)).to.eq(0);
      await cellar.setPause(false);

      const maxMint = await cellar.previewDeposit(Num(50_000, 6));
      expect(await cellar.maxMint(owner.address)).to.eq(maxMint);
      await USDC.mint(owner.address, maxMint);
      await cellar["mint(uint256,address)"](maxMint, owner.address);
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(Num(1.25, 27));
      expect(await cellar.maxMint(owner.address)).to.eq(0);

      await cellar.removeLiquidityRestriction();

      expect(await cellar.maxMint(owner.address)).to.eq(
        ethers.constants.MaxUint256
      );
    });

    it("should correctly find max withdraw amount", async () => {
      // test whether correctly simulates withdrawing own assets
      await cellar["deposit(uint256,address)"](Num(500, 6), owner.address);
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(Num(1.25, 27));
      await cellar["deposit(uint256,address)"](Num(500, 6), owner.address);

      const maxAssets = await cellar.maxWithdraw(owner.address);
      const ownedAssets = await cellar.callStatic.redeem(
        await cellar.balanceOf(owner.address),
        owner.address,
        owner.address
      );

      expect(ownedAssets).to.eq(maxAssets);
    });

    it("should correctly find max redeem amount", async () => {
      await cellar["deposit(uint256,address)"](Num(500, 6), owner.address);
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(Num(1.25, 27));
      await cellar["deposit(uint256,address)"](Num(500, 6), owner.address);

      const maxShares = await cellar.maxRedeem(owner.address);
      const shares = await cellar.balanceOf(owner.address);

      expect(shares).to.eq(maxShares);
    });
  });
});
