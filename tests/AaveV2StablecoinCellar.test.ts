import { ethers, network } from "hardhat";
import { expect } from "chai";
import {
  AaveV2StablecoinCellar,
  AaveV2StablecoinCellar__factory,
  MockAToken,
  MockAToken__factory,
  MockGravity,
  MockGravity__factory,
  MockIncentivesController,
  MockIncentivesController__factory,
  MockLendingPool,
  MockLendingPool__factory,
  MockStkAAVE,
  MockStkAAVE__factory,
  MockCurveSwaps,
  MockCurveSwaps__factory,
  MockSwapRouter,
  MockSwapRouter__factory,
  MockToken,
  MockToken__factory,
} from "../src/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";

const BigNum = (number: number, decimals: number) => {
  const [characteristic, mantissa] = number.toString().split(".");
  const padding = mantissa ? decimals - mantissa.length : decimals;
  return BigNumber.from(characteristic + (mantissa ?? "") + "0".repeat(padding));
};

const timestamp = async () => {
  const latestBlock = await ethers.provider.getBlock(await ethers.provider.getBlockNumber());

  return latestBlock.timestamp;
};

const timetravel = async (addTime: number) => {
  await ethers.provider.send("evm_increaseTime", [addTime]);
  await ethers.provider.send("evm_mine", []);
};

function getRandomInt(min: number, max: number) {
  min = Math.ceil(min);
  max = Math.floor(max);

  //The maximum is exclusive and the minimum is inclusive
  return Math.floor(Math.random() * (max - min) + min);
}

describe("AaveV2StablecoinCellar", () => {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let cellar: AaveV2StablecoinCellar;
  let USDC: MockToken;
  let WETH: MockToken;
  let DAI: MockToken;
  let USDT: MockToken;
  let curveRegistryExchange: MockCurveSwaps;
  let sushiswapRouter: MockSwapRouter;
  let lendingPool: MockLendingPool;
  let incentivesController: MockIncentivesController;
  let gravity: MockGravity;
  let aUSDC: MockAToken;
  let aDAI: MockAToken;
  let aUSDT: MockAToken;
  let stkAAVE: MockStkAAVE;
  let AAVE: MockToken;

  const impersonateGravity = async () => {
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [gravity.address],
    });

    // Sends ETH for sending transactions.
    await owner.sendTransaction({
      to: gravity.address,
      value: ethers.utils.parseEther("100.0"),
    });

    return ethers.provider.getSigner(gravity.address);
  };

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    // Deploy mock Sushiswap router contract
    sushiswapRouter = await new MockSwapRouter__factory(owner).deploy();
    await sushiswapRouter.deployed();

    // Deploy mock Curve registry exchange contract
    curveRegistryExchange = await new MockCurveSwaps__factory(owner).deploy();
    await curveRegistryExchange.deployed();

    // Deploy mock tokens
    USDC = await new MockToken__factory(owner).deploy("USDC", 6);
    DAI = await new MockToken__factory(owner).deploy("DAI", 18);
    WETH = await new MockToken__factory(owner).deploy("WETH", 18);
    USDT = await new MockToken__factory(owner).deploy("USDT", 6);

    await USDC.deployed();
    await DAI.deployed();
    await WETH.deployed();
    await USDT.deployed();

    // Deploy mock Aave lending pool
    lendingPool = await new MockLendingPool__factory(owner).deploy();
    await lendingPool.deployed();

    // Deploy mock aUSDC
    aUSDC = await new MockAToken__factory(owner).deploy(lendingPool.address, USDC.address, "aUSDC");
    await aUSDC.deployed();

    // Deploy mock aDAI
    aDAI = await new MockAToken__factory(owner).deploy(lendingPool.address, DAI.address, "aDAI");
    await aDAI.deployed();

    // Deploy mock aUSDT
    aUSDT = await new MockAToken__factory(owner).deploy(lendingPool.address, USDT.address, "aUSDT");
    await aUSDT.deployed();

    await lendingPool.initReserve(USDC.address, aUSDC.address);
    await lendingPool.initReserve(DAI.address, aDAI.address);
    await lendingPool.initReserve(USDT.address, aUSDT.address);

    // Deploy mock AAVE
    AAVE = await new MockToken__factory(owner).deploy("AAVE", 18);

    // Deploy mock stkAAVE
    stkAAVE = await new MockStkAAVE__factory(owner).deploy(AAVE.address);
    await stkAAVE.deployed();

    // Deploy mock Aave incentives controller
    incentivesController = await new MockIncentivesController__factory(owner).deploy(stkAAVE.address);
    await incentivesController.deployed();

    gravity = await new MockGravity__factory(owner).deploy();
    await gravity.deployed();

    // Deploy cellar contract
    cellar = await new AaveV2StablecoinCellar__factory(owner).deploy(
      USDC.address,
      curveRegistryExchange.address,
      sushiswapRouter.address,
      lendingPool.address,
      incentivesController.address,
      gravity.address,
      stkAAVE.address,
      AAVE.address,
      WETH.address,
    );
    await cellar.deployed();

    // Mint mock tokens to signers
    await USDC.mint(owner.address, BigNum(50_000, 6));
    await DAI.mint(owner.address, BigNum(50_000, 18));
    await WETH.mint(owner.address, BigNum(50_000, 18));
    await USDT.mint(owner.address, BigNum(50_000, 6));

    await USDC.mint(alice.address, BigNum(50_000, 6));
    await DAI.mint(alice.address, BigNum(50_000, 18));
    await WETH.mint(alice.address, BigNum(50_000, 18));
    await USDT.mint(alice.address, BigNum(50_000, 6));
    await USDC.mint(alice.address, BigNum(50_000, 6));

    await USDC.mint(bob.address, BigNum(50_000, 6));
    await DAI.mint(bob.address, BigNum(50_000, 18));
    await WETH.mint(bob.address, BigNum(50_000, 18));
    await USDT.mint(bob.address, BigNum(50_000, 6));

    // Approve cellar to spend mock tokens
    await USDC.approve(cellar.address, ethers.constants.MaxUint256);
    await DAI.approve(cellar.address, ethers.constants.MaxUint256);
    await WETH.approve(cellar.address, ethers.constants.MaxUint256);
    await USDT.approve(cellar.address, ethers.constants.MaxUint256);

    await USDC.connect(alice).approve(cellar.address, ethers.constants.MaxUint256);
    await DAI.connect(alice).approve(cellar.address, ethers.constants.MaxUint256);
    await WETH.connect(alice).approve(cellar.address, ethers.constants.MaxUint256);
    await USDT.connect(alice).approve(cellar.address, ethers.constants.MaxUint256);

    await USDC.connect(bob).approve(cellar.address, ethers.constants.MaxUint256);
    await DAI.connect(bob).approve(cellar.address, ethers.constants.MaxUint256);
    await WETH.connect(bob).approve(cellar.address, ethers.constants.MaxUint256);
    await USDT.connect(bob).approve(cellar.address, ethers.constants.MaxUint256);

    // Approve cellar to spend shares (to take as fees)
    await cellar.approve(cellar.address, ethers.constants.MaxUint256);

    await cellar.connect(alice).approve(cellar.address, ethers.constants.MaxUint256);

    await cellar.connect(bob).approve(cellar.address, ethers.constants.MaxUint256);

    // Mint initial liquidity to Aave lending pool
    await USDC.mint(aUSDC.address, BigNum(5_000_000, 6));
    await DAI.mint(aDAI.address, BigNum(5_000_000, 18));

    // Mint initial liquidity for swaps
    await USDC.mint(sushiswapRouter.address, BigNum(5_000_000, 6));
    await USDC.mint(curveRegistryExchange.address, BigNum(5_000_000, 6));
    await USDT.mint(curveRegistryExchange.address, BigNum(5_000_000, 6));
    await DAI.mint(curveRegistryExchange.address, BigNum(5_000_000, 18));
  });

  describe("deposit", () => {
    it("should mint correct amount of shares to user", async () => {
      // add $100 of inactive assets in cellar
      await cellar.deposit(BigNum(100, 6), owner.address);
      // expect 100 shares to be minted (because total supply of shares is 0)
      expect(await cellar.balanceOf(owner.address)).to.eq(BigNum(100, 18));

      // add $100 to inactive assets (w/o minting shares)
      await USDC.mint(cellar.address, BigNum(100, 6));

      // add $50 of inactive assets in cellar
      await cellar.connect(alice).deposit(BigNum(50, 6), alice.address);
      // expect 25 shares = 100 total shares * ($50 / $200) to be minted
      expect(await cellar.balanceOf(alice.address)).to.eq(BigNum(25, 18));
    });

    it("should transfer input token from user to cellar", async () => {
      const ownerOldBalance = await USDC.balanceOf(owner.address);
      const cellarOldBalance = await USDC.balanceOf(cellar.address);

      await cellar.deposit(BigNum(100, 6), owner.address);

      const ownerNewBalance = await USDC.balanceOf(owner.address);
      const cellarNewBalance = await USDC.balanceOf(cellar.address);

      // expect $100 to have been transferred from owner to cellar
      expect(ownerNewBalance.sub(ownerOldBalance)).to.eq(BigNum(-100, 6));
      expect(cellarNewBalance.sub(cellarOldBalance)).to.eq(BigNum(100, 6));
    });

    it("should mint shares to receiver instead of caller if specified", async () => {
      // owner mints to alice
      await cellar.deposit(BigNum(100, 6), alice.address);
      // expect alice receives 100 shares
      expect(await cellar.balanceOf(alice.address)).to.eq(BigNum(100, 18));
      // expect owner receives no shares
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
    });

    it("should deposit all user's balance if they try depositing more than their balance", async () => {
      const ownerBalance = await USDC.balanceOf(owner.address);
      const cellarBalance = await USDC.balanceOf(cellar.address);
      await cellar.deposit(ownerBalance.mul(2), owner.address);
      expect(await USDC.balanceOf(owner.address)).to.eq(0);
      expect(await USDC.balanceOf(cellar.address)).to.eq(cellarBalance.add(ownerBalance));
    });

    it("should use and store index of first non-zero deposit", async () => {
      await cellar.deposit(BigNum(100, 6), owner.address);
      // owner withdraws everything from deposit object at index 0
      await cellar.withdraw(BigNum(100, 6), owner.address, owner.address);
      // expect next non-zero deposit is set to index 1
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(1);

      await cellar.connect(alice).deposit(BigNum(100, 6), alice.address);
      // alice only withdraws half from index 0, leaving some shares remaining
      await cellar.connect(alice).withdraw(BigNum(50, 6), alice.address, alice.address);
      // expect next non-zero deposit is set to index 0 since some shares still remain
      expect(await cellar.currentDepositIndex(alice.address)).to.eq(0);
    });

    it("should not allow deposits of 0", async () => {
      await expect(cellar.deposit(0, owner.address)).to.be.revertedWith("USR_ZeroShares()");
    });

    it("should emit Deposit event", async () => {
      await expect(cellar.deposit(BigNum(1000, 6), alice.address))
        .to.emit(cellar, "Deposit")
        .withArgs(owner.address, alice.address, USDC.address, BigNum(1000, 6), BigNum(1000, 18));
    });
  });

  describe("mint", () => {
    it("should mint and deposit assets correctly", async () => {
      // has been tested successfully from 1 up to 100, but set to run once to avoid long test time
      for (let i = 100; i <= 100; i++) {
        const ownerOldBalance = await USDC.balanceOf(owner.address);

        const mintedShares = BigNum(i, 18);
        const currentShares = await cellar.balanceOf(owner.address);
        await cellar.mint(mintedShares, owner.address);
        expect(await cellar.balanceOf(owner.address)).to.eq(currentShares.add(mintedShares));
        expect(await USDC.balanceOf(owner.address)).to.eq(ownerOldBalance.sub(BigNum(i, 6)));
      }
    });

    it("should mint as much as possible if tries to mint more than they can", async () => {
      const balance = await USDC.balanceOf(owner.address);
      const maxShares = await cellar.previewDeposit(balance);

      await cellar.mint(maxShares.mul(2), owner.address);

      expect(await cellar.balanceOf(owner.address)).to.eq(maxShares);
    });
  });

  describe("withdraw", () => {
    beforeEach(async () => {
      // both owner and alice should start off owning 50% of the cellar's total assets each
      await cellar.deposit(BigNum(100, 6), owner.address);
      await cellar.connect(alice).deposit(BigNum(100, 6), alice.address);
    });

    it("should withdraw correctly when called with all inactive shares", async () => {
      const ownerOldBalance = await USDC.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $100 (50% of total)
      await cellar.withdraw(BigNum(100, 6), owner.address, owner.address);
      const ownerNewBalance = await USDC.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerNewBalance.sub(ownerOldBalance)).to.eq(BigNum(100, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await USDC.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $100 (50% of total)
      await cellar.connect(alice).withdraw(BigNum(100, 6), alice.address, alice.address);
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(BigNum(100, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with all active shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.connect(await impersonateGravity()).enterPosition();

      // mimic growth from $200 -> $250 (1.25x increase) while in position
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));

      const ownerOldBalance = await USDC.balanceOf(owner.address);
      await cellar.withdraw(BigNum(125, 6), owner.address, owner.address);
      const ownerNewBalance = await USDC.balanceOf(owner.address);
      // owner should be able redeem all shares for initial $125 (50% of total)
      expect(ownerNewBalance.sub(ownerOldBalance)).to.eq(BigNum(125, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await USDC.balanceOf(alice.address);
      await cellar.connect(alice).withdraw(BigNum(125, 6), alice.address, alice.address);
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      // alice should be able redeem all shares for initial $125 (50% of total)
      expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(BigNum(125, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw correctly when called with active and inactive shares", async () => {
      // convert all inactive assets -> active assets
      await cellar.connect(await impersonateGravity()).enterPosition();

      // mimic growth from $200 -> $250 (1.25x increase) while in position
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));

      // owner adds $100 of inactive assets
      await cellar.deposit(BigNum(100, 6), owner.address);
      // alice adds $75 of inactive assets
      await cellar.connect(alice).deposit(BigNum(75, 6), alice.address);

      const ownerOldBalance = await USDC.balanceOf(owner.address);
      await cellar.withdraw(BigNum(225, 6), owner.address, owner.address);
      const ownerNewBalance = await USDC.balanceOf(owner.address);
      // expect owner receives desired amount of tokens
      expect(ownerNewBalance.sub(ownerOldBalance)).to.eq(BigNum(100 + 125, 6));
      // expect all owner's shares to be burned
      expect(await cellar.balanceOf(owner.address)).to.eq(0);

      const aliceOldBalance = await USDC.balanceOf(alice.address);
      await cellar.connect(alice).withdraw(BigNum(200, 6), alice.address, alice.address);
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      // expect alice receives desired amount of tokens
      expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(BigNum(75 + 125, 6));
      // expect all alice's shares to be burned
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
    });

    it("should withdraw all user's assets if they try withdrawing more than their balance", async () => {
      await cellar.withdraw(BigNum(100, 6), owner.address, owner.address);
      // owner should now have nothing left to withdraw
      expect(await cellar.balanceOf(owner.address)).to.eq(0);
      await expect(cellar.withdraw(1, owner.address, owner.address)).to.be.revertedWith("USR_ZeroShares()");

      // alice only has $100 to withdraw, withdrawing $150 should only withdraw $100
      const aliceOldBalance = await USDC.balanceOf(alice.address);
      await cellar.connect(alice).withdraw(BigNum(150, 6), alice.address, alice.address);
      const aliceNewBalance = await USDC.balanceOf(alice.address);
      expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(BigNum(100, 6));
    });

    it("should not allow withdraws of 0", async () => {
      await expect(cellar.withdraw(0, owner.address, owner.address)).to.be.revertedWith("USR_ZeroAssets()");
    });

    it("should not allow unapproved account to withdraw using another's shares", async () => {
      const shares = BigNum(10, 18);

      // owner tries to withdraw alice's shares without approval (expect revert)
      await expect(cellar.redeem(shares, owner.address, alice.address)).to.be.reverted;

      await cellar.connect(alice).approve(owner.address, shares);

      // owner tries again after alice approved owner to withdraw $10 (expect pass)
      await cellar.redeem(shares, owner.address, alice.address);

      // owner tries to withdraw another $10 (expect revert)
      await expect(cellar.redeem(shares, owner.address, alice.address)).to.be.reverted;
    });

    it("should only withdraw from position if holding pool does not contain enough funds", async () => {
      await cellar.connect(await impersonateGravity()).enterPosition();
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));

      await cellar.connect(alice).deposit(BigNum(125, 6), alice.address);

      const beforeActiveAssets = await cellar.activeAssets();

      await cellar.withdraw(BigNum(125, 6), owner.address, owner.address);

      // active assets from position should not have changed
      expect(await cellar.activeAssets()).to.eq(beforeActiveAssets);
      // should have withdrawn from holding pool funds
      expect(await cellar.inactiveAssets()).to.eq(0);

      const beforeAliceBalance = await USDC.balanceOf(alice.address);

      const withdrawnAssets = BigNum(125, 6);
      await cellar.connect(alice).withdraw(withdrawnAssets, alice.address, alice.address);

      // should have withdrawn from Aave if holding pool is empty
      expect(await cellar.activeAssets()).to.eq(beforeActiveAssets.sub(withdrawnAssets));
      expect(await USDC.balanceOf(alice.address)).to.eq(beforeAliceBalance.add(withdrawnAssets));

      const yieldEarned = (await cellar.fees())[0];

      // should have updated yield
      expect(yieldEarned).to.eq(BigNum(50, 18));
    });

    it("should emit Withdraw event", async () => {
      await cellar.connect(await impersonateGravity()).enterPosition();
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));

      await expect(cellar.withdraw(BigNum(2000, 6), alice.address, owner.address))
        .to.emit(cellar, "Withdraw")
        .withArgs(alice.address, owner.address, USDC.address, BigNum(125, 6), BigNum(100, 18));
    });
  });

  describe("redeem", async () => {
    it("should redeem shares and withdraw assets correctly", async () => {
      // has been tested successfully from 1 up to 100, but set to run once to avoid long test time
      for (let i = 100; i <= 100; i++) {
        const shares = BigNum(i, 18);
        const ownerOldBalance = await USDC.balanceOf(owner.address);
        await cellar.mint(shares, owner.address);

        await cellar.redeem(shares, owner.address, owner.address);
        expect(await cellar.balanceOf(owner.address)).to.eq(0);
        expect(await USDC.balanceOf(owner.address)).to.eq(ownerOldBalance);
      }
    });

    it("should redeem as much as possible if tries to redeem more than they can", async () => {
      // has been tested successfully from 1 up to 100, but set to run once to avoid long test time
      for (let i = 100; i <= 100; i++) {
        const shares = BigNum(i, 18);
        await cellar.mint(shares, owner.address);

        await cellar.redeem(shares.mul(2), owner.address, owner.address);

        expect(await cellar.balanceOf(owner.address)).to.eq(0);
      }
    });
  });

  describe("transfer", () => {
    beforeEach(async () => {
      await cellar.deposit(BigNum(100, 6), owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
    });

    it("should correctly update deposit accounting upon transferring shares", async () => {
      // transferring active shares:

      const transferredActiveShares = BigNum(50, 18);

      const aliceOldBalance = await cellar.balanceOf(alice.address);
      await cellar.transfer(alice.address, transferredActiveShares);
      const aliceNewBalance = await cellar.balanceOf(alice.address);

      expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(transferredActiveShares);

      let ownerDeposit = await cellar.userDeposits(owner.address, 0);
      const aliceDeposit = await cellar.userDeposits(alice.address, 0);

      expect(ownerDeposit[0]).to.eq(0); // expect 0 assets (should have been deleted for a gas refund)
      expect(ownerDeposit[1]).to.eq(BigNum(50, 18)); // expect 50 shares
      expect(ownerDeposit[2]).to.eq(0); // expect 0 assets (should have been deleted for a gas refund)
      expect(aliceDeposit[0]).to.eq(0); // expect 0 assets (should have been deleted for a gas refund)
      expect(aliceDeposit[1]).to.eq(transferredActiveShares); // expect 50 shares
      expect(aliceDeposit[2]).to.eq(0); // expect 0 assets (should have been deleted for a gas refund)

      // transferring inactive shares:

      await cellar.connect(bob).deposit(BigNum(100, 6), bob.address);
      const depositTimestamp = await timestamp();

      const transferredInactiveShares = BigNum(25, 18);

      const ownerOldBalance = await cellar.balanceOf(owner.address);
      await cellar
        .connect(bob)
        ["transferFrom(address,address,uint256,bool)"](bob.address, owner.address, transferredInactiveShares, false);
      const ownerNewBalance = await cellar.balanceOf(owner.address);

      expect(ownerNewBalance.sub(ownerOldBalance)).to.eq(transferredInactiveShares);

      const bobDeposit = await cellar.userDeposits(bob.address, 0);
      ownerDeposit = await cellar.userDeposits(owner.address, 1);

      // must change decimals because deposit data is stored with 18 decimals
      expect(bobDeposit[0]).to.eq(BigNum(75, 18)); // expect 75 assets
      expect(bobDeposit[1]).to.eq(BigNum(75, 18)); // expect 75 shares
      expect(bobDeposit[2]).to.eq(depositTimestamp);
      expect(ownerDeposit[0]).to.eq(BigNum(25, 18)); // expect 25 assets
      expect(ownerDeposit[1]).to.eq(transferredInactiveShares); // expect 25 shares
      expect(ownerDeposit[2]).to.eq(depositTimestamp);
    });

    it("should correctly withdraw transferred shares", async () => {
      // $100 worth of active shares -> $125
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));

      // gain $100 worth of inactive shares
      await cellar.deposit(BigNum(100, 6), owner.address);

      // transfer all shares to alice
      await cellar["transferFrom(address,address,uint256,bool)"](
        owner.address,
        alice.address,
        await cellar.balanceOf(owner.address),
        false,
      );

      const aliceOldBalance = await USDC.balanceOf(alice.address);

      // alice redeem all the shares that have been transferred to her and withdraw all of her assets
      await cellar
        .connect(alice)
        .withdraw(await cellar.convertToAssets(await cellar.balanceOf(alice.address)), alice.address, alice.address);

      const aliceNewBalance = await USDC.balanceOf(alice.address);

      // expect alice to have redeemed all the shares transferred to her for $225 in assets
      expect(await cellar.balanceOf(alice.address)).to.eq(0);
      expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(BigNum(125 + 100, 6));
    });

    it("should only transfer active shares when specified", async () => {
      const expectedShares = await cellar.balanceOf(owner.address);

      // gain $100 worth of inactive shares
      await cellar.deposit(BigNum(100, 6), owner.address);

      const aliceOldBalance = await cellar.balanceOf(alice.address);

      // attempting to transfer all shares should only transfer $100 worth of active shares (and not
      // the $100 worth of inactive shares) and not revert
      await cellar["transferFrom(address,address,uint256,bool)"](
        owner.address,
        alice.address,
        await cellar.balanceOf(owner.address),
        true,
      );

      const aliceNewBalance = await cellar.balanceOf(alice.address);

      // expect alice to have received $100 worth of shares
      expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(expectedShares);
    });

    it("should use and store index of first non-zero deposit if not only active", async () => {
      await cellar.deposit(BigNum(100, 6), owner.address);
      // owner transfers all active shares from deposit object at index 0
      await cellar.transfer(alice.address, BigNum(100, 6));
      // expect next non-zero deposit is not have updated because onlyActive was true
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(0);

      // owner transfers everything from deposit object at index 1
      await cellar["transferFrom(address,address,uint256,bool)"](
        owner.address,
        alice.address,
        await cellar.balanceOf(owner.address),
        false,
      );
      // expect next non-zero deposit is set to index 2
      expect(await cellar.currentDepositIndex(owner.address)).to.eq(2);

      await cellar.connect(alice).deposit(BigNum(100, 6), alice.address);
      // alice only transfers half from index 0, leaving some shares remaining
      await cellar
        .connect(alice)
        ["transferFrom(address,address,uint256,bool)"](alice.address, owner.address, BigNum(50, 6), false);
      // expect next non-zero deposit is set to index 0 since some shares still remain
      expect(await cellar.currentDepositIndex(alice.address)).to.eq(0);
    });

    it("should require approval for transferring other's shares", async () => {
      await cellar.deposit(BigNum(100, 6), owner.address);
      await cellar.approve(alice.address, BigNum(50, 18));

      await cellar
        .connect(alice)
        ["transferFrom(address,address,uint256)"](owner.address, alice.address, BigNum(50, 18));

      await expect(cellar["transferFrom(address,address,uint256)"](alice.address, owner.address, BigNum(200, 18))).to.be
        .reverted;
    });
  });

  describe("enterPosition", () => {
    let holdingPoolAssets: BigNumber;
    let aaveOldBalance: BigNumber;

    beforeEach(async () => {
      holdingPoolAssets = BigNum(1000, 6);
      await cellar.deposit(holdingPoolAssets, owner.address);

      aaveOldBalance = await USDC.balanceOf(aUSDC.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
    });

    it("should deposit cellar inactive assets into Aave", async () => {
      expect(await USDC.balanceOf(cellar.address)).to.eq(0);
      expect(await USDC.balanceOf(aUSDC.address)).to.eq(aaveOldBalance.add(holdingPoolAssets));
    });

    it("should return correct amount of aTokens to cellar", async () => {
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(holdingPoolAssets);
    });

    it("should not allow deposit if cellar does not have enough liquidity", async () => {
      // cellar tries to enter position with $100 it does not have
      await expect(cellar.connect(await impersonateGravity()).enterPosition()).to.be.reverted;
    });

    it("should update yield", async () => {
      let yieldEarned = (await cellar.fees())[0];

      expect(yieldEarned).to.eq(0);

      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));

      await cellar.deposit(holdingPoolAssets, owner.address);

      await cellar.connect(await impersonateGravity()).enterPosition();

      yieldEarned = (await cellar.fees())[0];

      expect(yieldEarned).to.eq(BigNum(250, 18));
    });

    it("should emit DepositToAave and EnterPosition events", async () => {
      await cellar.deposit(BigNum(200, 6), owner.address);

      await expect(cellar.connect(await impersonateGravity()).enterPosition())
        .to.emit(cellar, "DepositToAave")
        .withArgs(USDC.address, BigNum(200, 6));

      await cellar.deposit(BigNum(200, 6), owner.address);

      await expect(cellar.connect(await impersonateGravity()).enterPosition())
        .to.emit(cellar, "EnterPosition")
        .withArgs(USDC.address, BigNum(200, 6));
    });
  });

  describe("claimAndUnstake", () => {
    beforeEach(async () => {
      // simulate cellar contract having 100 stkAAVE to claim
      await incentivesController.addRewards(cellar.address, BigNum(100, 18));
    });

    it("should claim rewards from Aave and begin unstaking", async () => {
      await cellar.connect(await impersonateGravity()).claimAndUnstake();

      // expect cellar to claim all 100 stkAAVE
      expect(await stkAAVE.balanceOf(cellar.address)).to.eq(BigNum(100, 18));
    });

    it("should have started 10 day unstaking cooldown period", async () => {
      await cellar.connect(await impersonateGravity()).claimAndUnstake();

      expect(await stkAAVE.stakersCooldowns(cellar.address)).to.eq(await timestamp());
    });

    it("should emits a ClaimAndUnstake event", async () => {
      await expect(cellar.connect(await impersonateGravity()).claimAndUnstake())
        .to.emit(cellar, "ClaimAndUnstake")
        .withArgs(BigNum(100, 18));
    });
  });

  describe("reinvest", () => {
    beforeEach(async () => {
      await incentivesController.addRewards(cellar.address, BigNum(100, 18));
      // cellar claims rewards and begins the 10 day cooldown period
      await cellar.connect(await impersonateGravity()).claimAndUnstake();

      await timetravel(864000);
    });

    it("should reinvested rewards back into principal", async () => {
      await cellar.connect(await impersonateGravity()).reinvest(0);

      expect(await stkAAVE.balanceOf(cellar.address)).to.eq(0);
      expect(await aUSDC.balanceOf(cellar.address)).to.eq(BigNum(95, 6));
    });

    it("should update yield", async () => {
      // mimic gaining $250 yield
      await aUSDC.mint(cellar.address, BigNum(250, 6), await lendingPool.index());

      await cellar.connect(await impersonateGravity()).reinvest(0);

      const yieldEarned = (await cellar.fees())[0];

      // $100 of reinvested rewards + $250 of interest earned - $5 lost on swap
      expect(yieldEarned).to.eq(BigNum(100 + 250 - 5, 18));
    });

    it("should emits a Reinvest event", async () => {
      await expect(cellar.connect(await impersonateGravity()).reinvest(0))
        .to.emit(cellar, "Reinvest")
        .withArgs(USDC.address, BigNum(100, 18), BigNum(95, 6));
    });
  });

  describe("rebalance", () => {
    beforeEach(async () => {
      await cellar.deposit(BigNum(1000, 6), owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
      await cellar.connect(alice).deposit(BigNum(500, 6), owner.address);
    });

    it("should rebalance all cellar assets into new assets", async () => {
      expect(await DAI.balanceOf(cellar.address)).to.eq(0);
      expect(await cellar.totalAssets()).to.eq(BigNum(1500, 6));

      await cellar.connect(await impersonateGravity()).setTrust(DAI.address, true);

      await cellar.connect(await impersonateGravity()).rebalance(
        [
          USDC.address,
          "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
          DAI.address,
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
        ],
        [
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
        ],
        0,
      );

      expect(await aUSDC.balanceOf(cellar.address)).to.eq(0);
      expect(await aDAI.balanceOf(cellar.address)).to.be.at.least(BigNum(950, 18));
    });

    it("should not be possible to rebalance from an asset other than the current asset", async () => {
      await cellar.connect(await impersonateGravity()).setTrust(USDT.address, true);

      await expect(
        cellar.connect(await impersonateGravity()).rebalance(
          [
            DAI.address,
            "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
            USDT.address,
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
          ],
          [
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
          ],
          0,
        ),
      ).to.be.reverted;
    });

    it("should not be possible to rebalance to the same token", async () => {
      const asset = await cellar.asset();
      await expect(
        cellar.connect(await impersonateGravity()).rebalance(
          [
            asset,
            "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
            asset,
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
          ],
          [
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
          ],
          0,
        ),
      ).to.be.revertedWith(`STATE_SameAsset("${asset}")`);
    });

    it("should update yield", async () => {
      // mimic gaining $250 yield in USDC
      await aUSDC.mint(cellar.address, BigNum(250, 6), await lendingPool.index());

      await cellar.connect(await impersonateGravity()).setTrust(DAI.address, true);

      await cellar.connect(await impersonateGravity()).rebalance(
        [
          USDC.address,
          "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
          DAI.address,
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
        ],
        [
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
        ],
        0,
      );

      let yieldEarned = (await cellar.fees())[0];
      expect(yieldEarned).to.eq(BigNum(250, 18));

      let lastActiveAssets = (await cellar.fees())[1];
      expect(lastActiveAssets).to.eq(await aDAI.balanceOf(cellar.address));

      // mimic gaining $250 yield in DAI
      await aDAI.mint(cellar.address, BigNum(250, 18), await lendingPool.index());

      await cellar.connect(await impersonateGravity()).rebalance(
        [
          DAI.address,
          "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
          USDC.address,
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
        ],
        [
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
        ],
        0,
      );

      yieldEarned = (await cellar.fees())[0];
      expect(yieldEarned).to.eq(BigNum(500, 18));

      lastActiveAssets = (await cellar.fees())[1];
      // must convert aUSDC from 6 -> 18 decimals
      expect(lastActiveAssets).to.eq((await aUSDC.balanceOf(cellar.address)).mul(1e12));
    });

    it("should update related state", async () => {
      await cellar.connect(await impersonateGravity()).setTrust(DAI.address, true);

      const tx = await cellar.connect(await impersonateGravity()).rebalance(
        [
          USDC.address,
          "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
          DAI.address,
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
        ],
        [
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
        ],
        0,
      );

      const receipt = await tx.wait();

      // should have updated current asset
      expect(await cellar.asset()).to.eq(DAI.address);

      // should have updated asset decimals
      expect(await cellar.assetDecimals()).to.eq(18);

      // should have updated asset decimals
      expect(await cellar.assetAToken()).to.eq(aDAI.address);

      // should have updated max liquidity
      expect(await cellar.maxLiquidity()).to.eq(BigNum(5_000_000, 18));

      // should have updated lastTimeEnteredPosition
      expect(await cellar.lastTimeEnteredPosition()).to.eq(
        (await ethers.provider.getBlock(receipt.blockNumber)).timestamp,
      );
    });

    it("should emits a Rebalance event", async () => {
      await cellar.connect(await impersonateGravity()).setTrust(DAI.address, true);

      await expect(
        cellar.connect(await impersonateGravity()).rebalance(
          [
            USDC.address,
            "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
            DAI.address,
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
          ],
          [
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
          ],
          0,
        ),
      )
        .to.emit(cellar, "Rebalance")
        .withArgs(USDC.address, DAI.address, BigNum(1425, 18));
    });
  });

  describe("accrueFees", () => {
    it("should accrue no fees when cellar has no active assets", async () => {
      await cellar.accrueFees();

      const accruedPlatformFees1 = (await cellar.fees())[3];
      const accruedPerformanceFees1 = (await cellar.fees())[4];

      expect(accruedPlatformFees1).to.eq(0);
      expect(accruedPerformanceFees1).to.eq(0);
    });

    it("should accrue platform fees", async () => {
      // owner deposits $1000
      await cellar.deposit(BigNum(1000, 6), owner.address);

      // convert all inactive assets -> active assets
      await cellar.connect(await impersonateGravity()).enterPosition();

      for (let i = 1; i <= 3; i++) {
        const accruedPlatformFeesBefore = (await cellar.fees())[3];
        const feesInAssetsBefore = await cellar.convertToAssets(accruedPlatformFeesBefore);

        const elapsedTime = getRandomInt(1, 7) * 86400;

        await timetravel(elapsedTime);

        await cellar.accrueFees();

        const accruedPlatformFees = (await cellar.fees())[3];
        const feesInAssets = await cellar.convertToAssets(accruedPlatformFees);

        // expect ~$0.027 worth of shares ($1000 * elapsedTime * (1% / secsPerYear)) in fees per accrual
        const expectedFeesAccrued = +(1000 * elapsedTime * (0.01 / 31536000)).toFixed(6);

        expect(feesInAssets).to.be.closeTo(feesInAssetsBefore.add(BigNum(expectedFeesAccrued, 6)), 1e2);
      }
    });

    it("should accrue performance fees", async () => {
      for (let i = 1; i <= 3; i++) {
        await cellar.deposit(BigNum(getRandomInt(201, 1000), 6), owner.address);

        // convert all inactive assets -> active assets
        await cellar.connect(await impersonateGravity()).enterPosition();

        // mimic gaining $250 yield
        await aUSDC.mint(cellar.address, BigNum(250, 6), await lendingPool.index());

        await cellar.withdraw(BigNum(getRandomInt(1, 200), 6), owner.address, owner.address);

        // should have ignored random deposits and withdraws
        const yieldEarned = (await cellar.fees())[0];
        expect(yieldEarned).to.eq(BigNum(250, 18));

        const expectedPerformanceFeesAccrued = await cellar.convertToShares(BigNum(25, 6));

        const tx = await cellar.accrueFees();
        const receipt = await tx.wait();

        const len = receipt.events?.length as number;
        const performanceFeesAccrued = await receipt.events![len - 1].args![0];

        expect(performanceFeesAccrued).to.be.closeTo(expectedPerformanceFeesAccrued, 1e11);
      }
    });
  });

  describe("transferFees", async () => {
    it("should be able to transfer fees to Cosmos", async () => {
      // accrue some platform fees
      await cellar.deposit(BigNum(1000, 6), owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
      await timetravel(86400); // 1 day
      await cellar.accrueFees();

      // accrue some performance fees
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));
      await cellar.accrueFees();

      const fees = await cellar.balanceOf(cellar.address);
      const accruedPlatformFees = (await cellar.fees())[3];
      const accruedPerformanceFees = (await cellar.fees())[4];

      expect(fees).to.eq(accruedPlatformFees.add(accruedPerformanceFees));

      const feeInAssets = await cellar.convertToAssets(fees);

      await cellar.connect(await impersonateGravity()).transferFees();

      // expect all fee shares to be transferred out
      expect(await cellar.balanceOf(cellar.address)).to.eq(0);
      expect(await USDC.balanceOf(gravity.address)).to.eq(feeInAssets);
    });

    it("should only withdraw from position if holding pool does not contain enough funds", async () => {
      // accrue some platform fees
      await cellar.deposit(BigNum(1000, 6), owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
      await timetravel(86400); // 1 day
      await cellar.accrueFees();

      // accrue some performance fees
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));
      await cellar.accrueFees();

      await cellar.connect(alice).deposit(BigNum(100, 6), alice.address);

      const beforeActiveAssets = await cellar.activeAssets();
      const beforeInactiveAssets = await cellar.inactiveAssets();

      // redeems fee shares for their underlying assets and sends them to Cosmos
      await cellar.connect(await impersonateGravity()).transferFees();

      const afterActiveAssets = await cellar.activeAssets();
      const afterInactiveAssets = await cellar.inactiveAssets();

      // active assets from position should not have changed
      expect(afterActiveAssets).to.eq(beforeActiveAssets);
      // should have withdrawn from holding pool funds
      expect(afterInactiveAssets.lt(beforeInactiveAssets)).to.be.true;
    });
  });

  describe("onlySteward", async () => {
    it("should prevent users from calling functions only callable from the gravity bridge", async () => {
      await expect(cellar.transferFees()).to.be.revertedWith("USR_NotGravityBridge()");
      await expect(cellar.enterPosition()).to.be.revertedWith("USR_NotGravityBridge()");
      await expect(cellar.setTrust(DAI.address, true)).to.be.revertedWith("USR_NotGravityBridge()");
      await expect(
        cellar.rebalance(
          [
            USDC.address,
            "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
            DAI.address,
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
          ],
          [
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
          ],
          0,
        ),
      ).to.be.revertedWith("USR_NotGravityBridge()");
    });

    await expect(cellar.reinvest(0)).to.be.revertedWith("USR_NotGravityBridge()");
    await expect(cellar.claimAndUnstake()).to.be.revertedWith("USR_NotGravityBridge()");
    await expect(cellar.sweep(DAI.address)).to.be.revertedWith("USR_NotGravityBridge()");
    await expect(cellar.removeLiquidityRestriction()).to.be.revertedWith("USR_NotGravityBridge()");
    await expect(cellar.removeDepositRestriction()).to.be.revertedWith("USR_NotGravityBridge()");
    await expect(cellar.setPause(true)).to.be.revertedWith("USR_NotGravityBridge()");
    await expect(cellar.shutdown()).to.be.revertedWith("USR_NotGravityBridge()");
  });

  describe("trust", async () => {
    beforeEach(async () => {
      await cellar.deposit(BigNum(1000, 6), owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
    });

    it("should prevent entering or rebalancing into untrusted position", async () => {
      await expect(
        cellar.connect(await impersonateGravity()).rebalance(
          [
            USDC.address,
            "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
            DAI.address,
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
          ],
          [
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
          ],
          0,
        ),
      ).to.be.revertedWith(`STATE_UntrustedPosition("${DAI.address}")`);

      await cellar.connect(await impersonateGravity()).setTrust(DAI.address, true);

      await cellar.connect(await impersonateGravity()).rebalance(
        [
          USDC.address,
          "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
          DAI.address,
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
        ],
        [
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0],
        ],
        0,
      );
    });

    await cellar.connect(await impersonateGravity()).setTrust(DAI.address, false);

    await expect(cellar.connect(await impersonateGravity()).enterPosition()).to.be.revertedWith(
      `STATE_UntrustedPosition("${DAI.address}")`,
    );

    await cellar.connect(await impersonateGravity()).setTrust(DAI.address, true);

    await cellar.connect(await impersonateGravity()).enterPosition();
  });

  describe("setTrust", async () => {
    beforeEach(async () => {
      const activeAssets = BigNum(1000, 6);

      await cellar.deposit(activeAssets, owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();

      expect(await cellar.activeAssets()).to.eq(activeAssets);

      // mimic growth from $1000 -> $1250 while in position
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));

      // distrust current position
      await cellar.connect(await impersonateGravity()).setTrust(USDC.address, false);
    });

    it("should withdraw all active assets if distrusting current position", async () => {
      expect(await cellar.activeAssets()).to.eq(0);
    });

    it("should update yield if withdrawing from distrusted position", async () => {
      const yieldEarned = (await cellar.fees())[0];

      expect(yieldEarned).to.eq(BigNum(250, 18));
    });
  });

  describe("pause", () => {
    it("should prevent users from depositing while paused", async () => {
      await cellar.connect(await impersonateGravity()).setPause(true);
      await expect(cellar.deposit(BigNum(100, 6), owner.address)).to.be.revertedWith("STATE_ContractPaused()");
    });

    it("should emits a Pause event", async () => {
      await expect(cellar.connect(await impersonateGravity()).setPause(true))
        .to.emit(cellar, "Pause")
        .withArgs(true);
    });
  });

  describe("shutdown", () => {
    it("should prevent users from depositing while shutdown", async () => {
      await cellar.deposit(BigNum(100, 6), owner.address);
      await cellar.connect(await impersonateGravity()).shutdown();
      await expect(cellar.deposit(BigNum(100, 6), owner.address)).to.be.revertedWith("STATE_ContractShutdown()");
    });

    it("should allow users to withdraw", async () => {
      // alice first deposits
      await cellar.connect(alice).deposit(BigNum(100, 6), alice.address);

      // cellar is shutdown
      await cellar.connect(await impersonateGravity()).shutdown();

      await cellar.connect(alice).withdraw(BigNum(100, 6), alice.address, alice.address);
    });

    it("should withdraw all active assets from Aave and update yield", async () => {
      await cellar.deposit(BigNum(1000, 6), owner.address);

      await cellar.connect(await impersonateGravity()).enterPosition();

      // mimic growth from $1000 -> $1250 (1.25x increase) while in position
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));

      await cellar.connect(await impersonateGravity()).shutdown();

      // expect all of active liquidity to be withdrawn from Aave
      expect(await USDC.balanceOf(cellar.address)).to.eq(BigNum(1250, 6));

      // should allow users to withdraw from holding pool
      await cellar.withdraw(BigNum(1250, 6), owner.address, owner.address);

      // should update yield
      const yieldEarned = (await cellar.fees())[0];
      expect(yieldEarned).to.eq(BigNum(250, 18));
    });

    it("should emit a Shutdown event", async () => {
      await expect(cellar.connect(await impersonateGravity()).shutdown()).to.emit(cellar, "Shutdown");
    });
  });

  describe("restrictions", () => {
    it("should prevent deposit if greater than max liquidity", async () => {
      // mint $5m to cellar (to hit liquidity cap)
      await USDC.mint(cellar.address, BigNum(5_000_000, 6));

      await expect(cellar.deposit(1, owner.address)).to.be.revertedWith(
        `STATE_LiquidityRestricted(${BigNum(5_000_000, 6)})`,
      );
    });

    it("should prevent deposit if greater than max deposit", async () => {
      await USDC.mint(owner.address, BigNum(50_001, 6));
      await expect(cellar.deposit(BigNum(50_001, 6), owner.address)).to.be.revertedWith(
        `USR_DepositRestricted(${BigNum(50_000, 6)})`,
      );

      await cellar.deposit(BigNum(50_000, 6), owner.address);
      await expect(cellar.deposit(1, owner.address)).to.be.revertedWith(`USR_DepositRestricted(${BigNum(50_000, 6)})`);
    });

    it("should allow deposits above max liquidity once restriction removed", async () => {
      // mint $5m to cellar (to hit liquidity cap)
      await USDC.mint(cellar.address, BigNum(5_000_000, 6));

      await cellar.connect(await impersonateGravity()).removeLiquidityRestriction();

      await cellar.deposit(1, owner.address);
    });

    it("should allow deposits above max deposit once restriction removed", async () => {
      await cellar.deposit(BigNum(50_000, 6), owner.address);

      await cellar.connect(await impersonateGravity()).removeDepositRestriction();

      await USDC.mint(owner.address, BigNum(1, 6));
      await cellar.deposit(1, owner.address);
    });
  });

  describe("sweep", () => {
    let SOMM: MockToken;

    beforeEach(async () => {
      SOMM = await new MockToken__factory(owner).deploy("SOMM", 18);
      await SOMM.deployed();

      // mimic 1000 SOMM being transferred to the cellar contract by accident
      await SOMM.mint(cellar.address, 1000);
    });

    it("should not allow assets managed by cellar to be transferred out", async () => {
      await expect(cellar.connect(await impersonateGravity()).sweep(USDC.address)).to.be.revertedWith(
        `STATE_ProtectedAsset("${USDC.address}")`,
      );
      await expect(cellar.connect(await impersonateGravity()).sweep(aUSDC.address)).to.be.revertedWith(
        `STATE_ProtectedAsset("${aUSDC.address}")`,
      );
      await expect(cellar.connect(await impersonateGravity()).sweep(cellar.address)).to.be.revertedWith(
        `STATE_ProtectedAsset("${cellar.address}")`,
      );
    });

    it("should recover tokens accidentally transferred to the contract", async () => {
      await cellar.connect(await impersonateGravity()).sweep(SOMM.address);

      // expect 1000 SOMM to have been transferred from cellar to owner
      expect(await SOMM.balanceOf(gravity.address)).to.eq(1000);
      expect(await SOMM.balanceOf(cellar.address)).to.eq(0);
    });

    it("should emit Sweep event", async () => {
      await expect(cellar.connect(await impersonateGravity()).sweep(SOMM.address))
        .to.emit(cellar, "Sweep")
        .withArgs(SOMM.address, 1000);
    });
  });

  describe("accounting", () => {
    let activeShares: BigNumber;
    let activeAssets: BigNumber;
    let inactiveShares: BigNumber;
    let inactiveAssets: BigNumber;

    beforeEach(async () => {
      await cellar.connect(bob).deposit(BigNum(12_345, 6), bob.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));

      activeShares = await cellar.balanceOf(bob.address);
      activeAssets = await cellar.previewRedeem(activeShares);

      inactiveAssets = BigNum(50_000, 6).sub(activeAssets);

      await cellar.connect(bob).deposit(inactiveAssets, bob.address);

      inactiveShares = (await cellar.balanceOf(bob.address)).sub(activeShares);
    });

    it("should accurately convert shares to assets and vice versa", async () => {
      // has been tested successfully from 1 up to 100, but set to run once to avoid long test time
      for (let i = 100; i <= 100; i++) {
        const initialAssets = BigNum(i, 6);
        const assetsToShares = await cellar.convertToShares(initialAssets);
        const sharesBackToAssets = await cellar.convertToAssets(assetsToShares);
        expect(sharesBackToAssets).to.eq(initialAssets);
        const assetsBackToShares = await cellar.convertToShares(sharesBackToAssets);
        expect(assetsBackToShares).to.eq(assetsToShares);
      }
    });

    it("should correctly preview deposits", async () => {
      // set to run only only once, but successfully from 1 to 1000 (max amount redeemable)
      for (let i = 100; i <= 100; i++) {
        const assets = BigNum(i, 6);

        const expectedShares = await cellar.previewDeposit(assets);
        const mintedShares = await cellar.callStatic.deposit(assets, owner.address);

        expect(expectedShares).to.eq(mintedShares);
      }
    });

    it("should correctly preview mint", async () => {
      await USDC.mint(owner.address, BigNum(1_000_000, 6));

      // set to run only only once, but successfully from 1 to 1000 (max amount redeemable)
      for (let i = 100; i <= 100; i++) {
        const shares = BigNum(i, 18);

        const expectedAssets = await cellar.previewMint(shares);
        const depositedAssets = await cellar.callStatic.mint(shares, owner.address);

        expect(depositedAssets).to.eq(expectedAssets);
      }
    });

    it("should correctly preview withdraws", async () => {
      await cellar.deposit(BigNum(1000, 6), owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();

      // set to run only only once, but successfully from 1 to 1000 (max amount withdrawable)
      for (let i = 100; i <= 100; i++) {
        const assets = BigNum(i, 6);

        const expectedShares = await cellar.previewWithdraw(assets);
        const redeemedShares = await cellar.callStatic.withdraw(assets, owner.address, owner.address);

        expect(redeemedShares).to.eq(expectedShares);
      }
    });

    it("should correctly preview redeems", async () => {
      await USDC.mint(owner.address, BigNum(1_000_000, 6));
      await cellar.mint(BigNum(1000, 18), owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();

      // set to run only only once, but successfully from 1 to 1000 (max amount redeemable)
      for (let i = 100; i <= 100; i++) {
        const shares = BigNum(i, 18);

        const expectedAssets = await cellar.previewRedeem(shares);
        const withdrawnAssets = await cellar.callStatic.redeem(shares, owner.address, owner.address);

        expect(withdrawnAssets).to.eq(expectedAssets);
      }
    });

    it("should accurately retrieve information on a user's deposit balances", async () => {
      const data = await cellar.getUserBalances(bob.address);

      expect(data[0].toString()).to.eq(activeShares);
      expect(data[1].toString()).to.eq(inactiveShares);
      expect(data[2].toString()).to.eq(activeAssets);
      expect(data[3].toString()).to.eq(inactiveAssets);
    });
  });

  describe("max", () => {
    it("should correctly find max deposit amount", async () => {
      await cellar.connect(await impersonateGravity()).setPause(true);
      expect(await cellar.maxDeposit(owner.address)).to.eq(0);
      await cellar.connect(await impersonateGravity()).setPause(false);

      const maxDeposit = BigNum(50_000, 6);
      expect(await cellar.maxDeposit(owner.address)).to.eq(maxDeposit);
      await USDC.mint(owner.address, maxDeposit);
      await cellar.deposit(maxDeposit, owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));
      expect(await cellar.maxDeposit(owner.address)).to.eq(0);
    });

    it("should correctly find max mint amount", async () => {
      await cellar.connect(await impersonateGravity()).setPause(true);
      expect(await cellar.maxMint(owner.address)).to.eq(0);
      await cellar.connect(await impersonateGravity()).setPause(false);

      const maxMint = await cellar.previewDeposit(BigNum(50_000, 6));
      expect(await cellar.maxMint(owner.address)).to.eq(maxMint);
      await USDC.mint(owner.address, maxMint);
      await cellar.mint(maxMint, owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));
      expect(await cellar.maxMint(owner.address)).to.eq(0);

      await cellar.connect(await impersonateGravity()).removeLiquidityRestriction();

      expect(await cellar.maxMint(owner.address)).to.eq(ethers.constants.MaxUint256);
    });

    it("should correctly find max withdraw amount", async () => {
      // test whether correctly simulates withdrawing own assets
      await cellar.deposit(BigNum(500, 6), owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));
      await cellar.deposit(BigNum(500, 6), owner.address);

      const maxAssets = await cellar.maxWithdraw(owner.address);
      const ownedAssets = await cellar.callStatic.redeem(
        await cellar.balanceOf(owner.address),
        owner.address,
        owner.address,
      );

      expect(ownedAssets).to.eq(maxAssets);
    });

    it("should correctly find max redeem amount", async () => {
      await cellar.deposit(BigNum(500, 6), owner.address);
      await cellar.connect(await impersonateGravity()).enterPosition();
      await lendingPool.setLiquidityIndex(BigNum(1.25, 27));
      await cellar.deposit(BigNum(500, 6), owner.address);

      const maxShares = await cellar.maxRedeem(owner.address);
      const shares = await cellar.balanceOf(owner.address);

      expect(shares).to.eq(maxShares);
    });
  });
});
