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
// - test withdrawing 0
// - test many transfers
// - test transferring active vs inactive shares
// - test view functions

describe("AaveV2StablecoinCellar", () => {
  let owner;
  let alice;
  let bob;
  let cellar;
  let Token;
  let usdc;
  let weth;
  let dai;
  let usdt;
  let router;
  let lendingPool;
  let incentivesController;
  let gravity;
  let aUSDC;
  let aDAI;
  let stkAAVE;
  let aave;

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    // Deploy mock Uniswap router contract
    const SwapRouter = await ethers.getContractFactory("MockSwapRouter");
    router = await SwapRouter.deploy();
    await router.deployed();

    // Deploy mock tokens
    Token = await ethers.getContractFactory("MockToken");
    usdc = await Token.deploy("USDC", 6);
    dai = await Token.deploy("DAI", 18);
    weth = await Token.deploy("WETH", 18);
    usdt = await Token.deploy("USDT", 6);

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
    aave = await Token.deploy("AAVE", 18);

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

    const MockGravity = await ethers.getContractFactory("MockGravity");
    gravity = await MockGravity.deploy();
    await gravity.deployed();

    // Deploy cellar contract
    const AaveV2StablecoinCellar = await ethers.getContractFactory(
      "AaveV2StablecoinCellar"
    );
    cellar = await AaveV2StablecoinCellar.deploy(
      router.address,
      router.address,
      lendingPool.address,
      incentivesController.address,
      gravity.address,
      stkAAVE.address,
      aave.address,
      weth.address,
      usdc.address,
      usdc.address
    );
    await cellar.deployed();

    // Mint mock tokens to signers
    await usdc.mint(owner.address, Num(1000, 6));
    await dai.mint(owner.address, Num(1000, 18));
    await weth.mint(owner.address, Num(1000, 18));
    await usdt.mint(owner.address, Num(1000, 6));

    await usdc.mint(alice.address, Num(1000, 6));
    await dai.mint(alice.address, Num(1000, 18));
    await weth.mint(alice.address, Num(1000, 18));
    await usdt.mint(alice.address, Num(1000, 6));

    // Approve cellar to spend mock tokens
    await usdc.approve(cellar.address, ethers.constants.MaxUint256);
    await dai.approve(cellar.address, ethers.constants.MaxUint256);
    await weth.approve(cellar.address, ethers.constants.MaxUint256);
    await usdt.approve(cellar.address, ethers.constants.MaxUint256);

    await usdc.connect(alice).approve(cellar.address, Num(1000, 6));
    await dai.connect(alice).approve(cellar.address, Num(1000, 18));
    await weth.connect(alice).approve(cellar.address, Num(1000, 18));
    await usdt.connect(alice).approve(cellar.address, Num(1000, 6));

    // Approve cellar to spend shares (to take as fees)
    await cellar.approve(cellar.address, ethers.constants.MaxUint256);

    await cellar
      .connect(alice)
      .approve(cellar.address, ethers.constants.MaxUint256);

    // Mint initial liquidity to Aave USDC lending pool
    await usdc.mint(aUSDC.address, Num(5000, 6));

    // Mint initial liquidity to router
    await usdc.mint(router.address, Num(5000, 6));
    await dai.mint(router.address, Num(5000, 18));
    await weth.mint(router.address, Num(5000, 18));
    await usdt.mint(router.address, Num(5000, 6));

    // Initialize with mock tokens as input tokens
    await cellar.setInputToken(usdc.address, true);
    await cellar.setInputToken(dai.address, true);
  });

  describe("deposit", () => {
    it("should mint correct amount of shares to user", async () => {
      // add $100 of inactive assets in cellar
      await cellar["deposit(uint256)"](Num(100, 6));
      // expect 100 shares to be minted (because total supply of shares is 0)
      expect(await cellar.balanceOf(owner.address)).to.eq(Num(100, 18));

      // add $100 to inactive assets (w/o minting shares)
      await usdc.mint(cellar.address, Num(100, 6));

      // add $50 of inactive assets in cellar
      await cellar.connect(alice)["deposit(uint256)"](Num(50, 6));
      // expect 25 shares = 100 total shares * ($50 / $200) to be minted
      expect(await cellar.balanceOf(alice.address)).to.eq(Num(25, 18));
    });

    it("should transfer input token from user to cellar", async () => {
      const ownerOldBalance = await usdc.balanceOf(owner.address);
      const cellarOldBalance = await usdc.balanceOf(cellar.address);

      await cellar["deposit(uint256)"](Num(100, 6));

      const ownerNewBalance = await usdc.balanceOf(owner.address);
      const cellarNewBalance = await usdc.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner to cellar
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(
        Num(-100, 6)
      );
      expect((cellarNewBalance - cellarOldBalance).toString()).to.eq(
        Num(100, 6)
      );
    });

    it("should swap input token for current lending token if not already", async () => {
      const ownerOldBalance = await dai.balanceOf(owner.address);
      const cellarOldBalance = await usdc.balanceOf(cellar.address);

      await cellar["deposit(address,uint256,uint256,address)"](
        dai.address,
        Num(100, 18),
        Num(95, 6),
        owner.address
      );

      const ownerNewBalance = await dai.balanceOf(owner.address);
      const cellarNewBalance = await usdc.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(
        Num(-100, 18)
      );
      // expect $95 to have been received by cellar (simulate $5 being lost during swap)
      expect((cellarNewBalance - cellarOldBalance).toString()).to.eq(
        Num(95, 6)
      );

      // expect shares to be minted to owner as if they deposited $95 even though
      // they deposited $100 (because that is what the cellar received after swap)
      expect(await cellar.balanceOf(owner.address)).to.eq(Num(95, 18));
    });

    it("should mint shares to receiver instead of caller if specified", async () => {
      // owner mints to alice
      await cellar["deposit(uint256,address)"](Num(100, 6), alice.address);
      // expect alice receives 100 shares
      expect(await cellar.balanceOf(alice.address)).to.eq(Num(100, 18));
      // expect owner receives no shares
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
    });

    it("should deposit all user's balance if tries to deposit more than they have", async () => {
      // owner has $1000 to deposit, withdrawing $5000 should only withdraw $1000
      await cellar["deposit(uint256)"](Num(5000, 6));
      expect(await usdc.balanceOf(owner.address)).to.eq(0);
      expect(await usdc.balanceOf(cellar.address)).to.eq(Num(1000, 6));
    });

    it("should emit Deposit event", async () => {
      await cellar.connect(alice)["deposit(uint256)"](Num(1000, 6));

      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );

      await expect(
        cellar["deposit(uint256,address)"](Num(2000, 6), alice.address)
      )
        .to.emit(cellar, "Deposit")
        .withArgs(
          owner.address,
          alice.address,
          usdc.address,
          Num(1000, 6),
          Num(800, 18)
        );
    });
  });

  describe("withdraw", () => {
    beforeEach(async () => {
      // both owner and alice should start off owning 50% of the cellar's total assets each
      await cellar["deposit(uint256)"](Num(100, 6));
      await cellar.connect(alice)["deposit(uint256)"](Num(100, 6));
    });

    it("should withdraw correctly when called with all inactive shares", async () => {
      const ownerOldBalance = await usdc.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $100 (50% of total)
      await cellar["withdraw(uint256)"](Num(100, 6));
      const ownerNewBalance = await usdc.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(Num(100, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await usdc.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $100 (50% of total)
      await cellar.connect(alice)["withdraw(uint256)"](Num(100, 6));
      const aliceNewBalance = await usdc.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(100, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with all active shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      // mimic growth from $200 -> $250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );

      const ownerOldBalance = await usdc.balanceOf(owner.address);
      await cellar["withdraw(uint256)"](Num(125, 6));
      const ownerNewBalance = await usdc.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $125 (50% of total)
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(Num(125, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await usdc.balanceOf(alice.address);
      await cellar.connect(alice)["withdraw(uint256)"](Num(125, 6));
      const aliceNewBalance = await usdc.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $125 (50% of total)
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(125, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with active and inactive shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      // mimic growth from $200 -> $250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );

      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](Num(100, 6));
      // alice adds $75 of inactive assets
      await cellar.connect(alice)["deposit(uint256)"](Num(75, 6));

      const ownerOldBalance = await usdc.balanceOf(owner.address);
      await cellar["withdraw(uint256)"](Num(225, 6));
      const ownerNewBalance = await usdc.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect((ownerNewBalance - ownerOldBalance).toString()).to.eq(
        Num(100 + 125, 6)
      );
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await usdc.balanceOf(alice.address);
      await cellar.connect(alice)["withdraw(uint256)"](Num(200, 6));
      const aliceNewBalance = await usdc.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(
        Num(75 + 125, 6)
      );
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw all user's assets if tries to withdraw more than they have", async () => {
      await cellar["withdraw(uint256)"](Num(100, 6));
      // owner should now have nothing left to withdraw
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
      await expect(cellar["withdraw(uint256)"](1)).to.be.revertedWith(
        "ZeroShares()"
      );

      // alice only has $100 to withdraw, withdrawing $150 should only withdraw $100
      const aliceOldBalance = await usdc.balanceOf(alice.address);
      await cellar.connect(alice)["withdraw(uint256)"](Num(150, 6));
      const aliceNewBalance = await usdc.balanceOf(alice.address);
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(Num(100, 6));
    });

    it("should not allow unapproved 3rd party to withdraw using another's shares", async () => {
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

    it("should emit Withdraw event", async () => {
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );

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
          usdc.address,
          Num(125, 6),
          Num(100, 18)
        );
    });
  });

  describe("transfer", () => {
    it("should correctly update deposit accounting upon transferring shares", async () => {
      // deposit $100 -> 100 shares
      await cellar["deposit(uint256)"](Num(100, 6));
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

    it("should allow withdrawing of transferred shares", async () => {
      await cellar["deposit(uint256)"](Num(100, 6));

      await cellar.transfer(alice.address, Num(100, 18));

      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );

      await cellar.connect(alice)["deposit(uint256)"](Num(100, 6));

      const aliceOldBalance = await usdc.balanceOf(alice.address);
      await cellar.connect(alice)["withdraw(uint256)"](Num(125 + 100, 6));
      const aliceNewBalance = await usdc.balanceOf(alice.address);

      expect(await cellar.balanceOf(alice.address)).to.eq(0);
      expect((aliceNewBalance - aliceOldBalance).toString()).to.eq(
        Num(125 + 100, 6)
      );
    });

    it("should require approval for transferring other's shares", async () => {
      await cellar.connect(alice)["deposit(uint256)"](Num(100, 6));
      await cellar.connect(alice).approve(owner.address, Num(50, 18));

      await cellar.transferFrom(alice.address, owner.address, Num(50, 18));
      await expect(
        cellar.transferFrom(alice.address, owner.address, Num(200, 18))
      ).to.be.reverted;
    });
  });

  describe("enterStrategy", () => {
    beforeEach(async () => {
      // owner adds $100 of inactive assets
      await cellar["deposit(uint256)"](Num(100, 6));

      // alice adds $100 of inactive assets
      await cellar.connect(alice)["deposit(uint256)"](Num(100, 6));

      // enter all $200 of inactive assets into a strategy
      await cellar.enterStrategy();
    });

    it("should deposit cellar inactive assets into Aave", async () => {
      // cellar's initial $200 - deposited $200 = $0
      expect(await usdc.balanceOf(cellar.address)).to.eq(0);
      // aave's initial $5000 + deposited $200 = $5200
      expect(await usdc.balanceOf(aUSDC.address)).to.eq(Num(5200, 6));
    });

    it("should return correct amount of aTokens to cellar", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(Num(200, 6));
    });

    it("should not allow deposit if cellar does not have enough liquidity", async () => {
      // cellar tries to enter strategy with $100 it does not have
      await expect(cellar.enterStrategy()).to.be.reverted;
    });

    it("should emit DepositToAave event", async () => {
      await cellar["deposit(uint256)"](Num(200, 6));

      await expect(cellar.enterStrategy())
        .to.emit(cellar, "DepositToAave")
        .withArgs(usdc.address, Num(200, 6));
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

      await cellar["reinvest(uint256)"](Num(95, 6));
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
  });

  describe("rebalance", () => {
    beforeEach(async () => {
      await cellar["deposit(uint256)"](Num(1000, 6));
      await cellar.enterStrategy();

      // set initial fee data
      await cellar.accrueFees();
    });

    it("should rebalance all usdc liquidity in dai", async () => {
      expect(await dai.balanceOf(cellar.address)).to.eq(0);
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(Num(1000, 6));

      await cellar.rebalance(dai.address, Num(950, 18));

      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
      expect(await aDAI.balanceOf(cellar.address)).to.be.at.least(Num(950, 18));
    });

    it("should not be possible to rebalance to the same token", async () => {
      await expect(cellar.rebalance(usdc.address, 0)).to.be.revertedWith(
        "SameLendingToken"
      );
    });

    it("should have accrued performance fees", async () => {
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );

      const accruedPerformanceFeesBefore = (await cellar.feesData())[4];
      const feesBefore = await cellar.balanceOf(cellar.address);

      const activeLiquidity = await cellar.activeAssets();
      await cellar.rebalance(dai.address, activeLiquidity * 0.95);

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
      await cellar["deposit(uint256)"](Num(1000, 6));

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await timetravel(86400); // 1 day

      await cellar.accrueFees();

      const accruedPlatformFees = (await cellar.feesData())[3];
      const feesInAssets = await cellar.convertToAssets(accruedPlatformFees);

      // ~$0.027 worth of shares in fees = $1000 * 86400 sec * (1% / secsPerYear)
      expect(feesInAssets).to.be.closeTo(Num(0.027, 6), Num(0.001, 6));
    });

    it("should accrue performance fees upon withdraw", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256)"](Num(1000, 6));

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await cellar.accrueFees();

      // mimic growth from $1000 -> $1250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );

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

    it("should burn performance fees with negative performance", async () => {
      // owner deposits $1000
      await cellar["deposit(uint256)"](Num(1000, 6));

      // convert all inactive assets -> active assets
      await cellar.enterStrategy();

      await cellar.accrueFees();

      // mimic growth from $1000 -> $1250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );

      await cellar.accrueFees();

      const feesBeforeLoss = ethers.BigNumber.from(
        await cellar.balanceOf(cellar.address)
      );

      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1150000000000000000000000000")
      );

      await cellar.accrueFees();

      const feesAfterLoss = ethers.BigNumber.from(
        await cellar.balanceOf(cellar.address)
      );

      // expect performance fee shares to have been burned
      expect(feesAfterLoss.lt(feesBeforeLoss)).to.be.true;
    });

    it("should be able to transfer fees to Cosmos", async () => {
      // accrue some platform fees
      await cellar["deposit(uint256)"](Num(1000, 6));
      await cellar.enterStrategy();
      await timetravel(86400); // 1 day
      await cellar.accrueFees();

      // accrue some performance fees
      await cellar.connect(alice)["deposit(uint256)"](Num(1000, 6));
      await cellar.enterStrategy();
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );
      await cellar.connect(alice)["withdraw(uint256)"](Num(1250, 6));
      await cellar.accrueFees();

      const fees = await cellar.balanceOf(cellar.address);
      const feeInAssets = await cellar.convertToAssets(fees);

      await cellar.transferFees();

      // expect all fee shares to be transferred out
      expect(await cellar.balanceOf(cellar.address)).to.eq(0);
      expect(await usdc.balanceOf(gravity.address)).to.eq(feeInAssets);
    });
  });

  describe("pause", () => {
    it("should prevent users from depositing while paused", async () => {
      await cellar.setPause(true);
      expect(cellar["deposit(uint256)"](Num(100, 6))).to.be.revertedWith(
        "ContractPaused()"
      );
    });

    it("should emits a Pause event", async () => {
      await expect(cellar.setPause(true))
        .to.emit(cellar, "Pause")
        .withArgs(owner.address, true);
    });
  });

  describe("shutdown", () => {
    it("should prevent users from depositing while shutdown", async () => {
      await cellar["deposit(uint256)"](Num(100, 6));
      await cellar.shutdown();
      expect(cellar["deposit(uint256)"](Num(100, 6))).to.be.revertedWith(
        "ContractShutdown()"
      );
    });

    it("should allow users to withdraw", async () => {
      // alice first deposits
      await cellar.connect(alice)["deposit(uint256)"](Num(100, 6));

      // cellar is shutdown
      await cellar.shutdown();

      await cellar.connect(alice)["withdraw(uint256)"](Num(100, 6));
    });

    it("should withdraw all active assets from Aave", async () => {
      await cellar["deposit(uint256)"](Num(1000, 6));

      await cellar.enterStrategy();

      // mimic growth from $1000 -> $1250 (1.25x increase) while in strategy
      await lendingPool.setLiquidityIndex(
        ethers.BigNumber.from("1250000000000000000000000000")
      );

      await cellar.shutdown();

      // expect all of active liquidity to be withdrawn from Aave
      expect(await usdc.balanceOf(cellar.address)).to.eq(Num(1250, 6));

      // should allow users to withdraw from holding pool
      await cellar["withdraw(uint256)"](Num(1250, 6));
    });

    it("should emit a Shutdown event", async () => {
      await expect(cellar.shutdown())
        .to.emit(cellar, "Shutdown")
        .withArgs(owner.address);
    });
  });

  describe("restrictLiquidity", () => {
    it("should prevent deposit it greater than max liquidity", async () => {
      // mint $5m to cellar (to hit liquidity cap)
      await usdc.mint(cellar.address, Num(5_000_000, 6));

      await expect(cellar["deposit(uint256)"](1)).to.be.revertedWith(
        `LiquidityRestricted(${Num(5_000_000, 6)})`
      );
    });

    it("should prevent deposit it greater than max deposit", async () => {
      await usdc.mint(owner.address, Num(50_001, 6));
      await expect(
        cellar["deposit(uint256)"](Num(50_001, 6))
      ).to.be.revertedWith(`DepositRestricted(${Num(50_000, 6)})`);

      await cellar["deposit(uint256)"](Num(50_000, 6));
      await expect(cellar["deposit(uint256)"](1)).to.be.revertedWith(
        `DepositRestricted(${Num(50_000, 6)})`
      );
    });

    it("should allow deposits above max liquidity once restriction removed", async () => {
      // mint $5m to cellar (to hit liquidity cap)
      await usdc.mint(cellar.address, Num(5_000_000, 6));

      await cellar.removeLiquidityRestriction();

      await cellar["deposit(uint256)"](Num(50_001, 6));
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
      await expect(cellar.sweep(usdc.address)).to.be.revertedWith(
        `ProtectedToken("${usdc.address}")`
      );
      await expect(cellar.sweep(aUSDC.address)).to.be.revertedWith(
        `ProtectedToken("${aUSDC.address}")`
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
});
