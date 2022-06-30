import { BigNumber } from "ethers";
import { ethers, waffle } from "hardhat";
import { BigNumberish } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { expect } from "chai";

const { loadFixture } = waffle;

import type { CellarStaking } from "../typechain-types";
import type { MockERC20 } from "../typechain-types";
import { Block } from "@ethersproject/providers";
import {
  ether,
  deploy,
  TestContext,
  increaseTime,
  rand,
  shuffle,
  setNextBlockTimestamp,
  expectRoundedEqual,
  claimWithRoundedRewardCheck,
  setupAdvancedScenario1,
  setupAdvancedScenario2,
  runScenario,
  fundAndApprove,
  setupAdvancedScenario3,
  setupAdvancedScenario4,
} from "./utils";

const oneDaySec = 60 * 60 * 24;
const oneWeekSec = oneDaySec * 7;
const oneMonthSec = oneDaySec * 30;

describe("CellarStaking", () => {
  let ctx: TestContext;
  const initialTokenAmount = ether("20000000"); // 20M

  // Lock enum
  const lockDay = 0;
  const lockWeek = 1;
  const lockTwoWeeks = 2;

  const fixture = async (): Promise<TestContext> => {
    // Signers
    const signers: SignerWithAddress[] = await ethers.getSigners();
    const admin = signers[0];
    const user = signers[1];

    // Bootstrap staking and distribution tokens
    const tokenStake = <MockERC20>await deploy("MockERC20", admin, ["stk", 18]);
    await tokenStake.mint(user.address, initialTokenAmount);

    const tokenDist = <MockERC20>await deploy("MockERC20", admin, ["dist", 18]);
    await tokenDist.mint(admin.address, initialTokenAmount);

    // Bootstrap CellarStaking contract
    const params = [
      admin.address,
      tokenStake.address,
      tokenDist.address,
      oneMonthSec,
      ether("0.1"),
      ether("0.4"),
      ether("1"),
      oneDaySec,
      oneWeekSec,
      oneWeekSec * 2,
    ];

    const staking = <CellarStaking>await deploy("CellarStaking", admin, params);
    const stakingUser = await staking.connect(user);

    // Fund staking contract with rewards
    await tokenDist.mint(staking.address, initialTokenAmount);

    // Allow staking contract to transfer on behalf of user
    const tokenStakeUser = await tokenStake.connect(user);
    await tokenStakeUser.approve(staking.address, initialTokenAmount);

    const connectUser = async (signer: SignerWithAddress): Promise<CellarStaking> => {
      const stake = await tokenStake.connect(signer);
      await stake.mint(signer.address, initialTokenAmount);
      await stake.approve(staking.address, initialTokenAmount);

      return staking.connect(signer);
    };

    return {
      admin,
      connectUser,
      signers,
      staking,
      stakingUser,
      tokenDist,
      tokenStake,
      user,
    };
  };

  beforeEach(async () => {
    ctx = await loadFixture(fixture);
  });

  describe("User Operations", () => {
    describe("stake, initialized to one wei per epoch sec", () => {
      beforeEach(async () => {
        await ctx.staking.notifyRewardAmount(oneMonthSec);
      });

      it("should not allow a user to stake if the stake is under the minimum", async () => {
        const { staking, stakingUser } = ctx;
        const min = ether("100");
        await staking.setMinimumDeposit(min);

        await expect(stakingUser.stake(min.sub(ether("1")), lockDay)).to.be.revertedWith("USR_MinimumDeposit");
      });

      it("should not allow a user to stake if there are no rewards left", async () => {
        const { stakingUser } = ctx;

        await stakingUser.stake(ether("1"), lockDay); // stake to start rewards
        await increaseTime(oneMonthSec * 2); // roll past reward time completion

        await expect(stakingUser.stake(ether("1"), lockDay)).to.be.revertedWith("STATE_NoRewardsLeft");
      });

      it("should not allow a user to stake if the amount is zero", async () => {
        const { stakingUser } = ctx;
        await expect(stakingUser.stake(0, lockDay)).to.be.revertedWith("USR_ZeroDeposit");
      });

      it("should not allow a user to stake if the contract is paused", async () => {
        const { staking, stakingUser } = ctx;

        await staking.setPaused(true);
        await expect(stakingUser.stake(ether("1"), lockDay)).to.be.revertedWith("STATE_ContractPaused");
      });

      it("should revert for an invalid lock value", async () => {
        const { stakingUser } = ctx;
        await expect(stakingUser.stake(ether("1"), 99)).to.be.revertedWith(
          "function was called with incorrect parameter",
        );
      });

      it("should allow one user to stake with 100% proportional share", async () => {
        const { stakingUser, user } = ctx;
        const stakeAmount = ether("100000");

        await expect(stakingUser.stake(stakeAmount, lockDay))
          .to.emit(stakingUser, "Stake")
          .withArgs(user.address, 0, stakeAmount);

        const stake = await stakingUser.stakes(user.address, 0);
        const totalDeposits = await stakingUser.totalDeposits();
        const totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        const rewardPerTokenStored = await stakingUser.rewardPerTokenStored();

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.amount).to.equal(totalDeposits);
        expect(stake.amountWithBoost).to.equal(totalDepositsWithBoost);
        expect(stake.rewardPerTokenPaid).to.equal(rewardPerTokenStored);
        expect(stake.rewards).to.equal(0);
        expect(stake.unbondTimestamp).to.equal(0);
        expect(stake.lock).to.equal(lockDay);
      });

      it("should calculate the correct boosts for different lock times", async () => {
        const { stakingUser, user } = ctx;
        const stakeAmount = ether("100000");

        await expect(stakingUser.stake(stakeAmount, lockDay)).to.not.be.reverted;
        await expect(stakingUser.stake(stakeAmount, lockWeek)).to.not.be.reverted;
        await expect(stakingUser.stake(stakeAmount, lockTwoWeeks)).to.not.be.reverted;

        let stake = await stakingUser.stakes(user.address, 0);
        let boostMultiplier = stakeAmount.mul(await stakingUser.SHORT_BOOST()).div(ether("1"));
        let expectedAmountWithBoost = stakeAmount.add(boostMultiplier);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.amountWithBoost).to.equal(expectedAmountWithBoost);

        stake = await stakingUser.stakes(user.address, 1);
        boostMultiplier = stakeAmount.mul(await stakingUser.MEDIUM_BOOST()).div(ether("1"));
        expectedAmountWithBoost = stakeAmount.add(boostMultiplier);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.amountWithBoost).to.equal(expectedAmountWithBoost);

        stake = await stakingUser.stakes(user.address, 2);
        boostMultiplier = stakeAmount.mul(await stakingUser.LONG_BOOST()).div(ether("1"));
        expectedAmountWithBoost = stakeAmount.add(boostMultiplier);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.amountWithBoost).to.equal(expectedAmountWithBoost);
      });

      it("should allow two users to stake with an even proportional share", async () => {
        const { connectUser, signers, stakingUser, user } = ctx;
        const amount = 100000;
        await stakingUser.stake(amount, lockDay);

        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);
        await stakingUser2.stake(amount, lockDay);

        const stakes = await stakingUser.stakes(user.address, 0);
        const stakes2 = await stakingUser.stakes(user2.address, 0);

        const totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes.amountWithBoost).to.equal(totalDepositsWithBoost.div(2));
        expect(stakes.amountWithBoost).to.equal(stakes2.amountWithBoost);
      });

      it("should allow three users to stake with an even proportional share", async () => {
        const { connectUser, signers, stakingUser, user } = ctx;
        const amount = 100000;
        await stakingUser.stake(amount, lockDay);

        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);
        await stakingUser2.stake(amount, lockDay);

        const user3 = signers[3];
        const stakingUser3 = await connectUser(user3);
        await stakingUser3.stake(amount, lockDay);

        const stakes = await stakingUser.stakes(user.address, 0);
        const stakes2 = await stakingUser.stakes(user2.address, 0);
        const stakes3 = await stakingUser.stakes(user3.address, 0);

        const totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes.amountWithBoost).to.equal(totalDepositsWithBoost.div(3));
        expect(stakes.amountWithBoost).to.equal(stakes2.amountWithBoost);
        expect(stakes.amountWithBoost).to.equal(stakes3.amountWithBoost);
      });

      it("should correctly calculate shares for a 60/40 stake between two users", async () => {
        const x = 0.6;
        const y = 0.4;
        const { connectUser, signers, stakingUser, user } = ctx;
        const amount = 100000;
        await stakingUser.stake(amount * x, lockDay);

        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);
        await stakingUser2.stake(amount * y, lockDay);

        const stakes = await stakingUser.stakes(user.address, 0);
        const stakes2 = await stakingUser.stakes(user2.address, 0);
        const totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes.amountWithBoost).to.equal(totalDepositsWithBoost.div(10).mul(x * 10));
        expect(stakes2.amountWithBoost).to.equal(totalDepositsWithBoost.div(10).mul(y * 10));
      });

      it("should correctly calculate stake shares for two users", async () => {
        // number of runs
        const times = 10;

        for (let i = 0; i < times; i++) {
          ctx = await loadFixture(fixture);
          await ctx.staking.setRewardsDuration(oneDaySec);
          await ctx.staking.notifyRewardAmount(oneDaySec);
          const { connectUser, signers, stakingUser, user } = ctx;

          // javascript floating point arithmetic is imprecise
          // user1 stakes x (x is a range 50-100 inclusive)
          // user2 stakes 100 - x
          const x = rand(50, 99);
          const amount1 = initialTokenAmount.div(100).mul(x);
          const amount2 = initialTokenAmount.sub(amount1);

          await stakingUser.stake(amount1, lockDay);

          const user2 = signers[2];
          const stakingUser2 = await connectUser(user2);
          await stakingUser2.stake(amount2, lockDay);

          const stakes1 = (await stakingUser.stakes(user.address, 0)).amountWithBoost;
          const stakes2 = (await stakingUser.stakes(user2.address, 0)).amountWithBoost;
          const totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();

          const expected1 = stakes1.mul(initialTokenAmount).div(totalDepositsWithBoost);
          const expected2 = stakes2.mul(initialTokenAmount).div(totalDepositsWithBoost);
          expect(expected1).to.equal(amount1);
          expect(expected2).to.equal(amount2);
        }
      });

      it("fuzzing with random number of users and staked amounts", async () => {
        // global fuzzing parameters
        const times = 1;
        const minStake = 100; //100000
        const maxStake = 10000; //initialTokenAmount

        for (let i = 0; i < times; i++) {
          // reset fixture
          ctx = await loadFixture(fixture);
          await ctx.staking.setRewardsDuration(oneDaySec);
          await ctx.staking.notifyRewardAmount(oneDaySec);
          const { connectUser } = ctx;

          // setup fuzzing scenario
          const numUsers = rand(2, 19); // Max signers = 10 because 0 is admin
          const signers = <SignerWithAddress[]>[...Array(numUsers).keys()].map(i => ctx.signers[i + 1]);
          const amounts = new Map<SignerWithAddress, BigNumber>();
          let totalStaked = BigNumber.from(0);

          // stake a random amount for each signer
          for (const signer of signers) {
            const staking = await connectUser(signer);
            const amount = ethers.utils.parseEther(rand(minStake, maxStake).toString()); // inclusive
            await staking.stake(amount, lockDay);

            amounts.set(signer, amount);
            totalStaked = totalStaked.add(BigNumber.from(amount));
          }

          const totalDepositsWithBoost = await ctx.staking.totalDepositsWithBoost();

          for (const signer of signers) {
            const amount = amounts.get(signer);
            const share = (await ctx.staking.stakes(signer.address, 0)).amountWithBoost;

            // shares * totalStaked / totalShares = stakedAmount
            const expected = share.mul(totalStaked).div(totalDepositsWithBoost);
            expect(expected).to.equal(amount);
          }
        }
      });

      it("should properly calculate a user's proportional share with one day boost", async () => {
        const { connectUser, signers, stakingUser } = ctx;
        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);

        // user 2 stakes 50, should get 55 shares with a 10% boost
        await stakingUser2.stake(50, lockDay);
        const stakes2 = await stakingUser2.stakes(user2.address, 0);

        const expected2 = 55;
        let totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes2.amountWithBoost).to.equal(expected2);
        expect(totalDepositsWithBoost).to.equal(expected2);

        // user 1 stakes 100, should get 110 shares
        await stakingUser.stake(100, lockDay);
        const stakes = await stakingUser.stakes(signers[1].address, 0);

        const expected = 110;
        totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes.amountWithBoost).to.equal(expected);
        expect(totalDepositsWithBoost).to.equal(expected + expected2);

        // user 2 stakes again, 99. should get 108 shares
        await stakingUser2.stake(99, lockDay);
        const stakes3 = await stakingUser2.stakes(user2.address, 1);

        const expected3 = 108; // 99 * 1.1
        totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes3.amountWithBoost).to.equal(expected3);
        expect(totalDepositsWithBoost).to.equal(expected + expected2 + expected3);
      });

      it("should properly calculate a user's proportional share with one week boost", async () => {
        const { connectUser, signers, stakingUser } = ctx;
        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);

        // user 2 stakes 50, should get 70 shares with a 40% boost
        await stakingUser2.stake(50, lockWeek);
        const stakes2 = await stakingUser2.stakes(user2.address, 0);

        const expected2 = 70; // 50 * 1.4
        let totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes2.amountWithBoost).to.equal(expected2);
        expect(totalDepositsWithBoost).to.equal(expected2);

        // user 1 stakes 100, should get 140 shares
        await stakingUser.stake(100, lockWeek);
        const stakes = await stakingUser.stakes(signers[1].address, 0);

        const expected = 140;
        totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes.amountWithBoost).to.equal(expected);
        expect(totalDepositsWithBoost).to.equal(expected + expected2);

        // user 2 stakes again, 297. should get 415 shares due to rounding down
        await stakingUser2.stake(297, lockWeek);
        const stakes3 = await stakingUser2.stakes(user2.address, 1);

        const expected3 = 415; // 297 * 1.4 floored
        totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes3.amountWithBoost).to.equal(expected3);
        expect(totalDepositsWithBoost).to.equal(expected + expected2 + expected3);
      });

      it("should properly calculate a user's proportional share with two week boost", async () => {
        const { connectUser, signers, stakingUser } = ctx;
        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);

        // user 2 stakes 88, should get 176 shares with a 100% boost
        await stakingUser2.stake(88, lockTwoWeeks);
        const stakes2 = await stakingUser2.stakes(user2.address, 0);

        const expected2 = 176;
        let totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes2.amountWithBoost).to.equal(expected2);
        expect(totalDepositsWithBoost).to.equal(expected2);

        // user 1 stakes 100, should get 482 shares
        await stakingUser.stake(241, lockTwoWeeks);
        const stakes = await stakingUser.stakes(signers[1].address, 0);

        const expected = 482;
        totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes.amountWithBoost).to.equal(expected);
        expect(totalDepositsWithBoost).to.equal(expected + expected2);

        // user 2 stakes again, 832. should get 1664 shares
        await stakingUser2.stake(832, lockTwoWeeks);
        const stakes3 = await stakingUser2.stakes(user2.address, 1);

        const expected3 = 1664;
        totalDepositsWithBoost = await stakingUser.totalDepositsWithBoost();
        expect(stakes3.amountWithBoost).to.equal(expected3);
        expect(totalDepositsWithBoost).to.equal(expected + expected2 + expected3);
      });
    });

    describe("unbond", () => {
      const rewardPerEpoch = ether(oneWeekSec.toString());
      const stakeAmount = ether("1000");

      beforeEach(async () => {
        await ctx.staking.setRewardsDuration(oneWeekSec);

        await ctx.staking.notifyRewardAmount(rewardPerEpoch);
        await ctx.stakingUser.stake(stakeAmount, lockDay);
      });

      it("should revert if passed an out of bounds deposit ID", async () => {
        const { stakingUser } = ctx;
        await expect(stakingUser.unbond(2)).to.be.reverted;
      });

      it("should revert if the specified deposit is already unbonding", async () => {
        const { stakingUser } = ctx;
        await expect(stakingUser.unbond(0)).to.not.be.reverted;

        await expect(stakingUser.unbond(0)).to.be.revertedWith("USR_AlreadyUnbonding");
      });

      it("should not allow a user to unbond if the contract is paused", async () => {
        const { staking, stakingUser } = ctx;

        await staking.setPaused(true);
        await expect(stakingUser.unbond(0)).to.be.revertedWith("STATE_ContractPaused");
      });

      it("should unbond a stake and remove any boosts", async () => {
        const { stakingUser, user } = ctx;

        const stake = await stakingUser.stakes(user.address, 0);
        const boostMultiplier = stakeAmount.mul(await stakingUser.SHORT_BOOST()).div(ether("1"));
        const expectedAmountWithBoost = stakeAmount.add(boostMultiplier);
        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.amountWithBoost).to.equal(expectedAmountWithBoost);
        expect(stake.unbondTimestamp).to.equal(0);
        expect(stake.lock).to.equal(lockDay);

        await expect(stakingUser.unbond(0)).to.emit(stakingUser, "Unbond").withArgs(user.address, 0, stakeAmount);

        // Check updated stake
        const updatedStake = await stakingUser.stakes(user.address, 0);
        const latestBlock = await ethers.provider.getBlock("latest");

        expect(updatedStake.amount).to.equal(stakeAmount);
        expect(updatedStake.amountWithBoost).to.equal(stakeAmount);
        expect(updatedStake.unbondTimestamp).to.equal(latestBlock.timestamp + oneDaySec);
        expect(updatedStake.lock).to.equal(lockDay);
      });
    });

    describe("unbondAll", () => {
      const rewardPerEpoch = ether(oneWeekSec.toString());
      const stakeAmount = ether("1000");

      it("should not allow a user to unbond all stakes if the contract is paused", async () => {
        const { staking, stakingUser } = ctx;

        await staking.setRewardsDuration(oneWeekSec);

        await staking.notifyRewardAmount(rewardPerEpoch);
        await stakingUser.stake(stakeAmount, lockDay);

        // Stake again
        await stakingUser.stake(stakeAmount.mul(2), lockWeek);
        await stakingUser.stake(stakeAmount.mul(3), lockTwoWeeks);

        await staking.setPaused(true);
        await expect(stakingUser.unbondAll()).to.be.revertedWith("STATE_ContractPaused");
      });

      it("should unbond all stakes, skipping ones that have already been unbonded", async () => {
        const { staking, stakingUser, user } = ctx;

        await staking.setRewardsDuration(oneWeekSec);

        await staking.notifyRewardAmount(rewardPerEpoch);
        await stakingUser.stake(stakeAmount, lockDay);

        // Stake again
        await stakingUser.stake(stakeAmount.mul(2), lockWeek);
        await stakingUser.stake(stakeAmount.mul(3), lockTwoWeeks);

        // Unbond one stake
        await expect(stakingUser.unbond(1))
          .to.emit(stakingUser, "Unbond")
          .withArgs(user.address, 1, stakeAmount.mul(2));

        // Check updated stake
        let updatedStake = await stakingUser.stakes(user.address, 1);
        let latestBlock = await ethers.provider.getBlock("latest");

        expect(updatedStake.amount).to.equal(stakeAmount.mul(2));
        expect(updatedStake.amountWithBoost).to.equal(stakeAmount.mul(2));
        expect(updatedStake.unbondTimestamp).to.equal(latestBlock.timestamp + oneWeekSec);
        expect(updatedStake.lock).to.equal(lockWeek);

        const tx = await stakingUser.unbondAll();
        const receipt = await tx.wait();

        const unbondEvents = await receipt.events?.filter(e => e.event === "Unbond");
        expect(unbondEvents?.length === 2);

        // Check other stakes updated
        updatedStake = await stakingUser.stakes(user.address, 0);
        latestBlock = await ethers.provider.getBlock("latest");

        expect(updatedStake.amount).to.equal(stakeAmount);
        expect(updatedStake.amountWithBoost).to.equal(stakeAmount);
        expect(updatedStake.unbondTimestamp).to.equal(latestBlock.timestamp + oneDaySec);
        expect(updatedStake.lock).to.equal(lockDay);

        updatedStake = await stakingUser.stakes(user.address, 2);

        expect(updatedStake.amount).to.equal(stakeAmount.mul(3));
        expect(updatedStake.amountWithBoost).to.equal(stakeAmount.mul(3));
        expect(updatedStake.unbondTimestamp).to.equal(latestBlock.timestamp + oneWeekSec * 2);
        expect(updatedStake.lock).to.equal(lockTwoWeeks);
      });
    });

    describe("cancelUnbonding", () => {
      const rewardPerEpoch = ether(oneWeekSec.toString());
      const stakeAmount = ether("1000");

      beforeEach(async () => {
        await ctx.staking.setRewardsDuration(oneWeekSec);

        await ctx.staking.notifyRewardAmount(rewardPerEpoch);
        await ctx.stakingUser.stake(stakeAmount, lockDay);
      });

      it("should revert if passed an out of bounds deposit ID", async () => {
        const { stakingUser } = ctx;
        await expect(stakingUser.cancelUnbonding(2)).to.be.reverted;
      });

      it("should revert if the specified deposit is not unbonding", async () => {
        const { stakingUser } = ctx;
        await expect(stakingUser.cancelUnbonding(0)).to.be.revertedWith("USR_NotUnbonding");
      });

      it("should not allow a user to cancel unbonding if the contract is paused", async () => {
        const { staking, stakingUser } = ctx;

        await expect(stakingUser.unbond(0)).to.not.be.reverted;

        await staking.setPaused(true);
        await expect(stakingUser.cancelUnbonding(0)).to.be.revertedWith("STATE_ContractPaused");
      });

      it("should cancel unbonding for a stake and reinstate any boosts", async () => {
        const { stakingUser, user } = ctx;

        const stake = await stakingUser.stakes(user.address, 0);
        const boostMultiplier = stakeAmount.mul(await stakingUser.SHORT_BOOST()).div(ether("1"));
        const expectedAmountWithBoost = stakeAmount.add(boostMultiplier);
        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.amountWithBoost).to.equal(expectedAmountWithBoost);
        expect(stake.unbondTimestamp).to.equal(0);
        expect(stake.lock).to.equal(lockDay);

        await expect(stakingUser.unbond(0)).to.not.be.reverted;

        // Check updated stake
        const updatedStake = await stakingUser.stakes(user.address, 0);
        const latestBlock = await ethers.provider.getBlock("latest");

        expect(updatedStake.amount).to.equal(stakeAmount);
        expect(updatedStake.amountWithBoost).to.equal(stakeAmount);
        expect(updatedStake.unbondTimestamp).to.equal(latestBlock.timestamp + oneDaySec);
        expect(updatedStake.lock).to.equal(lockDay);

        // Now cancel
        await expect(stakingUser.cancelUnbonding(0)).to.emit(stakingUser, "CancelUnbond").withArgs(user.address, 0);

        const originalStake = await stakingUser.stakes(user.address, 0);

        expect(originalStake.amount).to.equal(stakeAmount);
        expect(originalStake.amountWithBoost).to.equal(expectedAmountWithBoost);
        expect(originalStake.unbondTimestamp).to.equal(0);
        expect(originalStake.lock).to.equal(lockDay);
      });
    });

    describe("cancelUnbondingAll", () => {
      const rewardPerEpoch = ether(oneWeekSec.toString());
      const stakeAmount = ether("1000");

      it("should not allow a user to cancel unbonding if the contract is paused", async () => {
        const { staking, stakingUser } = ctx;

        await staking.setRewardsDuration(oneWeekSec);

        await staking.notifyRewardAmount(rewardPerEpoch);
        await stakingUser.stake(stakeAmount, lockDay);

        // Stake again
        await stakingUser.stake(stakeAmount, lockWeek);
        await stakingUser.stake(stakeAmount, lockTwoWeeks);

        // Unbond two stakes
        await expect(stakingUser.unbond(1)).to.not.be.reverted;
        await expect(stakingUser.unbond(2)).to.not.be.reverted;

        await staking.setPaused(true);
        await expect(stakingUser.cancelUnbondingAll()).to.be.revertedWith("STATE_ContractPaused");
      });

      it("should cancel unbonding all stakes, skipping ones that are not unbonding", async () => {
        const { staking, stakingUser, user } = ctx;

        await staking.setRewardsDuration(oneWeekSec);

        await staking.notifyRewardAmount(rewardPerEpoch);
        await stakingUser.stake(stakeAmount, lockDay);

        // Stake again
        await stakingUser.stake(stakeAmount, lockWeek);
        await stakingUser.stake(stakeAmount, lockTwoWeeks);

        // Unbond two stakes
        await expect(stakingUser.unbond(1)).to.not.be.reverted;
        await expect(stakingUser.unbond(2)).to.not.be.reverted;

        const tx = await stakingUser.cancelUnbondingAll();
        const receipt = await tx.wait();

        const cancelEvents = await receipt.events?.filter(e => e.event === "CancelUnbond");
        expect(cancelEvents?.length === 2);

        // Check all stakes match original
        let stake = await stakingUser.stakes(user.address, 0);
        let boostMultiplier = stakeAmount.mul(await stakingUser.SHORT_BOOST()).div(ether("1"));
        let expectedAmountWithBoost = stakeAmount.add(boostMultiplier);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.amountWithBoost).to.equal(expectedAmountWithBoost);
        expect(stake.unbondTimestamp).to.equal(0);
        expect(stake.lock).to.equal(lockDay);

        stake = await stakingUser.stakes(user.address, 1);
        boostMultiplier = stakeAmount.mul(await stakingUser.MEDIUM_BOOST()).div(ether("1"));
        expectedAmountWithBoost = stakeAmount.add(boostMultiplier);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.amountWithBoost).to.equal(expectedAmountWithBoost);
        expect(stake.unbondTimestamp).to.equal(0);
        expect(stake.lock).to.equal(lockWeek);

        stake = await stakingUser.stakes(user.address, 2);
        boostMultiplier = stakeAmount.mul(await stakingUser.LONG_BOOST()).div(ether("1"));
        expectedAmountWithBoost = stakeAmount.add(boostMultiplier);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.amountWithBoost).to.equal(expectedAmountWithBoost);
        expect(stake.unbondTimestamp).to.equal(0);
        expect(stake.lock).to.equal(lockTwoWeeks);
      });
    });

    describe("unstake", () => {
      const rewardPerEpoch = ether(oneWeekSec.toString());
      const stakeAmount = ether("1000");

      beforeEach(async () => {
        await ctx.staking.setRewardsDuration(oneWeekSec);

        await ctx.staking.notifyRewardAmount(rewardPerEpoch);
        await ctx.stakingUser.stake(stakeAmount, lockDay);
      });

      it("should revert if passed an out of bounds deposit id", async () => {
        const { stakingUser } = ctx;
        await expect(stakingUser.unstake(2)).to.be.reverted;
      });

      it("should not allow unstaking a stake that is still locked", async () => {
        const { stakingUser } = ctx;
        await expect(stakingUser.unstake(0)).to.be.revertedWith("USR_StakeLocked");
      });

      it("should not allow a user to unstake if the contract is paused", async () => {
        const { staking, stakingUser } = ctx;

        await expect(stakingUser.unbond(0)).to.not.be.reverted;

        await staking.setPaused(true);
        await expect(stakingUser.unstake(0)).to.be.revertedWith("STATE_ContractPaused");
      });

      it("should not allow unstaking if the unbonding period has not expired", async () => {
        const { stakingUser, user } = ctx;

        await increaseTime(oneWeekSec);

        // Unbond one stake
        await expect(stakingUser.unbond(0)).to.emit(stakingUser, "Unbond").withArgs(user.address, 0, stakeAmount);

        // Check updated stake
        const updatedStake = await stakingUser.stakes(user.address, 0);
        const latestBlock = await ethers.provider.getBlock("latest");

        expect(updatedStake.amount).to.equal(stakeAmount);
        expect(updatedStake.amountWithBoost).to.equal(stakeAmount);
        expect(updatedStake.unbondTimestamp).to.equal(latestBlock.timestamp + oneDaySec);
        expect(updatedStake.lock).to.equal(lockDay);

        // try to very soon after unstake
        await increaseTime(1000);
        await expect(stakingUser.unstake(0)).to.be.revertedWith("USR_StakeLocked");
      });

      it("should require a non-zero amount to unstake", async () => {
        const { stakingUser, user, tokenDist } = ctx;

        await increaseTime(oneWeekSec);
        await stakingUser.unbond(0);

        const prevBal = await tokenDist.balanceOf(user.address);

        const stake = await stakingUser.stakes(user.address, 0);
        await setNextBlockTimestamp(stake.unbondTimestamp + 1);

        const tx = await stakingUser.unstake(0);
        const receipt = await tx.wait();

        const unstakeEvent = receipt.events?.find(e => e.event === "Unstake");

        expect(unstakeEvent).to.not.be.undefined;
        expect(unstakeEvent?.args?.[0]).to.equal(user.address);
        expect(unstakeEvent?.args?.[1]).to.equal(0);
        expect(unstakeEvent?.args?.[2]).to.equal(stakeAmount);
        expectRoundedEqual(unstakeEvent?.args?.[3], rewardPerEpoch);

        // single staker takes all rewards
        const bal = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(bal.sub(prevBal), rewardPerEpoch);
      });

      it("should not unstake more than the deposited amount", async () => {
        const { stakingUser, user, tokenStake } = ctx;

        await increaseTime(oneWeekSec);
        await stakingUser.unbond(0);

        const prevBal = await tokenStake.balanceOf(user.address);

        const stake = await stakingUser.stakes(user.address, 0);
        await setNextBlockTimestamp(stake.unbondTimestamp + 1);

        await stakingUser.unstake(0);

        // previous bal + staked amount should equal current balance
        const bal = await tokenStake.balanceOf(user.address);
        expect(prevBal.add(stakeAmount)).to.equal(bal);
      });

      it("should unstake, distributing both the specified deposit amount and any accumulated rewards", async () => {
        const { stakingUser, user, tokenStake, tokenDist } = ctx;

        await increaseTime(oneWeekSec);
        await stakingUser.unbond(0);

        const prevBal = await tokenStake.balanceOf(user.address);

        const stake = await stakingUser.stakes(user.address, 0);
        await setNextBlockTimestamp(stake.unbondTimestamp + 1);

        await stakingUser.unstake(0);

        // previous bal + staked amount should equal current balance
        const bal = await tokenStake.balanceOf(user.address);
        expect(prevBal.add(stakeAmount)).to.equal(bal);

        const rewardsBal = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(rewardsBal, rewardPerEpoch);
      });
    });

    describe("unstakeAll", () => {
      const rewardPerEpoch = ether(String(2_000_000)); // 2M
      const stakeAmount = ether("50000");

      beforeEach(async () => {
        await ctx.staking.setRewardsDuration(oneWeekSec * 3);
        await ctx.staking.notifyRewardAmount(rewardPerEpoch.mul(3));
        await ctx.stakingUser.stake(stakeAmount, lockDay);
      });

      it("should not allow a user to unstake all stakes if the contract is paused", async () => {
        const { staking, stakingUser } = ctx;

        await stakingUser.stake(stakeAmount, lockDay);

        // Stake again
        await stakingUser.stake(stakeAmount, lockWeek);
        await stakingUser.stake(stakeAmount, lockTwoWeeks);

        // Unbond two stakes
        await expect(stakingUser.unbond(1)).to.not.be.reverted;
        await expect(stakingUser.unbond(2)).to.not.be.reverted;

        // End rewards
        await increaseTime(oneWeekSec * 3);

        await staking.setPaused(true);
        await expect(stakingUser.unstakeAll()).to.be.revertedWith("STATE_ContractPaused");
      });

      it("should unstake all amounts for all deposits, and distribute all available rewards", async () => {
        const { connectUser, signers, stakingUser, user, tokenDist, tokenStake } = ctx;
        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);

        // user1 should collect all of first week reward
        await increaseTime(oneWeekSec);

        // week 2 and 3 reward should be split 2/3 to 1/3
        await stakingUser2.stake(stakeAmount, lockDay);
        await stakingUser.stake(stakeAmount, lockDay);

        // End rewards
        await increaseTime(oneWeekSec * 3);

        await stakingUser.unbondAll();
        await stakingUser2.unbondAll();

        const prevStakeBal = await tokenStake.balanceOf(user.address);
        const prevDistBalUser1 = await tokenDist.balanceOf(user.address);
        const prevDistBalUser2 = await tokenDist.balanceOf(user2.address);

        const stake = await stakingUser.stakes(user.address, 0);
        await setNextBlockTimestamp(stake.unbondTimestamp + 1);

        await stakingUser.unstakeAll();
        await stakingUser2.unstakeAll();

        // expect to recover balance that was initially staked
        const totalStaked = stakeAmount.mul(2);
        const stakeBal = await tokenStake.balanceOf(user.address);

        expect(prevStakeBal.add(BigNumber.from(totalStaked))).to.equal(stakeBal);

        // expect to collect all rewards of first week, and 2/3 rewards of weeks 2 and 3
        // for 7/9 total
        const expectedRewardsUser1 = rewardPerEpoch.div(3).mul(7);
        const distBalUser1 = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(distBalUser1.sub(prevDistBalUser1), expectedRewardsUser1);

        const expectedRewardsUser2 = rewardPerEpoch.div(3).mul(2);
        const distBalUser2 = await tokenDist.balanceOf(user2.address);
        expectRoundedEqual(distBalUser2.sub(prevDistBalUser2), expectedRewardsUser2);
      });
    });

    describe("claim", () => {
      const rewardPerEpoch = ether(oneWeekSec.toString());
      const stakeAmount = ether("1000");

      beforeEach(async () => {
        await ctx.staking.setRewardsDuration(oneWeekSec);
        await ctx.staking.notifyRewardAmount(rewardPerEpoch);
        await ctx.stakingUser.stake(stakeAmount, lockDay);
      });

      it("claims available rewards for a given deposit", async () => {
        const { stakingUser, user, tokenDist } = ctx;

        // Run through rewards time - should get all
        await increaseTime(oneWeekSec);

        const balanceBefore = await tokenDist.balanceOf(user.address);

        const tx = await stakingUser.claim(0);
        const receipt = await tx.wait();

        const claimEvent = receipt.events?.find(e => e.event === "Claim");

        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user.address);
        expect(claimEvent?.args?.[1]).to.equal(0);
        expectRoundedEqual(claimEvent?.args?.[2], rewardPerEpoch);

        // Check rewards are reset
        const stake = await stakingUser.stakes(user.address, 0);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.rewards).to.equal(0);

        // Check rewards are in wallet
        const balanceAfter = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(balanceAfter.sub(balanceBefore), rewardPerEpoch);
      });

      it("should correctly calculate rewards for two claims", async () => {
        const { connectUser, signers, stakingUser, user, tokenDist } = ctx;
        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);

        await stakingUser2.stake(stakeAmount, lockDay);

        // Run through rewards time - should be all distributed
        await increaseTime(oneWeekSec);

        const balanceBeforeUser1 = await tokenDist.balanceOf(user.address);
        const balanceBeforeUser2 = await tokenDist.balanceOf(user2.address);

        let tx = await stakingUser.claim(0);
        let receipt = await tx.wait();

        let claimEvent = receipt.events?.find(e => e.event === "Claim");

        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user.address);
        expect(claimEvent?.args?.[1]).to.equal(0);
        expectRoundedEqual(claimEvent?.args?.[2], rewardPerEpoch.div(2));

        await increaseTime(oneWeekSec);

        tx = await stakingUser2.claim(0);
        receipt = await tx.wait();

        claimEvent = receipt.events?.find(e => e.event === "Claim");

        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user2.address);
        expect(claimEvent?.args?.[1]).to.equal(0);
        expectRoundedEqual(claimEvent?.args?.[2], rewardPerEpoch.div(2));

        // Check rewards are reset
        let stake = await stakingUser.stakes(user.address, 0);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.rewards).to.equal(0);

        stake = await stakingUser.stakes(user2.address, 0);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.rewards).to.equal(0);

        // Check rewards are in wallet
        const balanceAfterUser1 = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(balanceAfterUser1.sub(balanceBeforeUser1), rewardPerEpoch.div(2));

        const balanceAfterUser2 = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(balanceAfterUser2.sub(balanceBeforeUser2), rewardPerEpoch.div(2));
      });

      it("should correctly calculate rewards for subsequent claims", async () => {
        const { stakingUser, user, tokenDist } = ctx;

        // Run through half time - should get half
        await increaseTime(oneWeekSec / 2);

        const balanceBefore = await tokenDist.balanceOf(user.address);

        let tx = await stakingUser.claim(0);
        let receipt = await tx.wait();

        let claimEvent = receipt.events?.find(e => e.event === "Claim");

        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user.address);
        expect(claimEvent?.args?.[1]).to.equal(0);
        expectRoundedEqual(claimEvent?.args?.[2], rewardPerEpoch.div(2));

        // Check rewards are reset
        let stake = await stakingUser.stakes(user.address, 0);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.rewards).to.equal(0);

        // Check rewards are in wallet
        let balanceAfter = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(balanceAfter.sub(balanceBefore), rewardPerEpoch.div(2));

        // Run through the next half, should get another half rewards
        await increaseTime(oneWeekSec / 2);

        const balanceIntermediate = balanceAfter;

        tx = await stakingUser.claim(0);
        receipt = await tx.wait();

        claimEvent = receipt.events?.find(e => e.event === "Claim");

        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user.address);
        expect(claimEvent?.args?.[1]).to.equal(0);
        expectRoundedEqual(claimEvent?.args?.[2], rewardPerEpoch.div(2));

        // Check rewards are reset
        stake = await stakingUser.stakes(user.address, 0);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.rewards).to.equal(0);

        // Check rewards are in wallet
        balanceAfter = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(balanceAfter.sub(balanceIntermediate), rewardPerEpoch.div(2));
      });

      it("should correctly calculate proportional rewards across different user stakes", async () => {
        const { stakingUser, user, tokenDist } = ctx;

        // Should get larger boost
        await stakingUser.stake(stakeAmount, lockWeek);

        // Run through rewards time - should be all distributed
        await increaseTime(oneWeekSec);

        // Should be 110 vs. 140 for two stakes - 250 total

        const balanceBefore = await tokenDist.balanceOf(user.address);

        let tx = await stakingUser.claim(0);
        let receipt = await tx.wait();

        let claimEvent = receipt.events?.find(e => e.event === "Claim");

        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user.address);
        expect(claimEvent?.args?.[1]).to.equal(0);
        expectRoundedEqual(claimEvent?.args?.[2], rewardPerEpoch.div(25).mul(11));

        // Check rewards are reset
        let stake = await stakingUser.stakes(user.address, 0);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.rewards).to.equal(0);

        // Claim second stake
        tx = await stakingUser.claim(1);
        receipt = await tx.wait();

        claimEvent = receipt.events?.find(e => e.event === "Claim");

        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user.address);
        expect(claimEvent?.args?.[1]).to.equal(1);
        expectRoundedEqual(claimEvent?.args?.[2], rewardPerEpoch.div(25).mul(14));

        stake = await stakingUser.stakes(user.address, 1);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.rewards).to.equal(0);

        // Check rewards are in wallet
        const balanceAfter = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(balanceAfter.sub(balanceBefore), rewardPerEpoch);
      });

      it("should not redistribute rewards that have already been claimed", async () => {
        const { stakingUser, user, tokenDist } = ctx;

        // Run through rewards time - should get all
        await increaseTime(oneWeekSec);

        const balanceBefore = await tokenDist.balanceOf(user.address);

        await expect(stakingUser.claim(0)).to.not.be.reverted;

        // Check rewards are reset
        const stake = await stakingUser.stakes(user.address, 0);

        expect(stake.amount).to.equal(stakeAmount);
        expect(stake.rewards).to.equal(0);

        // Check rewards are in wallet
        const balanceAfter = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(balanceAfter.sub(balanceBefore), rewardPerEpoch);

        // Try to claim again
        const tx = await stakingUser.claim(0);
        const receipt = await tx.wait();

        const claimEvent = receipt.events?.find(e => e.event === "Claim");
        expect(claimEvent).to.be.undefined;

        // No rewards claimed
        expect(await tokenDist.balanceOf(user.address)).to.equal(balanceAfter);
      });
    });

    describe("claimAll", () => {
      const rewardPerEpoch = ether(String(2_000_000)); // 2M
      const stakeAmount = ether("50000");

      it("should claim all available rewards for all deposits", async () => {
        const { connectUser, signers, staking, stakingUser, user, tokenDist } = ctx;

        await staking.setRewardsDuration(oneWeekSec * 3);
        await staking.notifyRewardAmount(rewardPerEpoch.mul(3));
        await stakingUser.stake(stakeAmount, lockDay);

        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);

        // user1 should collect all of first week reward
        await increaseTime(oneWeekSec);

        // week 2 and 3 reward should be split 2/3 to 1/3
        await stakingUser2.stake(stakeAmount, lockDay);
        await stakingUser.stake(stakeAmount, lockDay);

        // End rewards
        await increaseTime(oneWeekSec * 3);

        const prevDistBalUser1 = await tokenDist.balanceOf(user.address);
        const prevDistBalUser2 = await tokenDist.balanceOf(user2.address);

        await stakingUser.claimAll();
        await stakingUser2.claimAll();

        // expect to collect all rewards of first week, and 2/3 rewards of weeks 2 and 3
        // for 7/9 total
        const expectedRewardsUser1 = rewardPerEpoch.div(3).mul(7);
        const distBalUser1 = await tokenDist.balanceOf(user.address);
        expectRoundedEqual(distBalUser1.sub(prevDistBalUser1), expectedRewardsUser1);

        const expectedRewardsUser2 = rewardPerEpoch.div(3).mul(2);
        const distBalUser2 = await tokenDist.balanceOf(user2.address);
        expectRoundedEqual(distBalUser2.sub(prevDistBalUser2), expectedRewardsUser2);
      });
    });

    describe("emergencyUnstake", () => {
      const rewardPerEpoch = ether(oneWeekSec.toString());

      beforeEach(async () => {
        await ctx.staking.setRewardsDuration(oneWeekSec);
        await ctx.staking.notifyRewardAmount(rewardPerEpoch);
      });

      it("should revert if the staking program has not been ended", async () => {
        const { stakingUser } = ctx;

        await expect(stakingUser.emergencyUnstake()).to.be.revertedWith("STATE_NoEmergencyUnstake");
      });

      it("should return all staked tokens, across multiple stakes, regardless of lock status", async () => {
        const { connectUser, signers, staking, stakingUser, tokenStake, user } = ctx;
        await stakingUser.stake(initialTokenAmount, lockDay);
        expect(await tokenStake.balanceOf(user.address)).to.equal(0);

        const user2 = signers[2];
        const stakingUser2 = await connectUser(user2);
        await stakingUser2.stake(initialTokenAmount, lockWeek);
        expect(await tokenStake.balanceOf(user2.address)).to.equal(0);

        const user3 = signers[3];
        const stakingUser3 = await connectUser(user3);
        await stakingUser3.stake(initialTokenAmount, lockTwoWeeks);
        expect(await tokenStake.balanceOf(user3.address)).to.equal(0);

        await expect(staking.emergencyStop(false))
          .to.emit(staking, "EmergencyStop")
          .withArgs(signers[0].address, false);

        await expect(stakingUser.emergencyUnstake())
          .to.emit(stakingUser, "EmergencyUnstake")
          .withArgs(user.address, 0, initialTokenAmount);
        expect(await tokenStake.balanceOf(user.address)).to.equal(initialTokenAmount);

        await expect(stakingUser2.emergencyUnstake())
          .to.emit(stakingUser2, "EmergencyUnstake")
          .withArgs(user2.address, 0, initialTokenAmount);
        expect(await tokenStake.balanceOf(user2.address)).to.equal(initialTokenAmount);

        await expect(stakingUser3.emergencyUnstake())
          .to.emit(stakingUser3, "EmergencyUnstake")
          .withArgs(user3.address, 0, initialTokenAmount);
        expect(await tokenStake.balanceOf(user3.address)).to.equal(initialTokenAmount);
      });

      it("should emergency unstake multiple stakes for the same user", async () => {
        const { staking, stakingUser, tokenStake, user } = ctx;
        const stakeAmount = initialTokenAmount.div(2);

        await stakingUser.stake(stakeAmount, lockDay);
        await stakingUser.stake(stakeAmount, lockWeek);

        expect(await tokenStake.balanceOf(user.address)).to.equal(0);

        await expect(staking.emergencyStop(false)).to.not.be.reverted;

        const tx = await stakingUser.emergencyUnstake();
        const receipt = await tx.wait();

        const unstakeEvents = await receipt.events?.filter(e => e.event === "Unbond");
        expect(unstakeEvents?.length === 2);

        for (const i in unstakeEvents!) {
          const event = unstakeEvents[i];
          expect(event?.args?.[0]).to.equal(user.address);
          expect(event?.args?.[1]).to.equal(i);
          expect(event?.args?.[2]).to.equal(stakeAmount);
        }

        expect(await tokenStake.balanceOf(user.address)).to.equal(initialTokenAmount);
      });

      it("should not allow users to claim rewards", async () => {
        const { staking, stakingUser } = ctx;

        await stakingUser.stake(initialTokenAmount, lockDay);
        await expect(staking.emergencyStop(false)).to.not.be.reverted;

        await stakingUser.emergencyUnstake();

        // Try to claim rewards normally
        await expect(stakingUser.claim(0)).to.be.revertedWith("STATE_ContractKilled");
        await expect(stakingUser.claimAll()).to.be.revertedWith("STATE_ContractKilled");

        // Try to claim rewards thru emergency
        await expect(stakingUser.emergencyClaim()).to.be.revertedWith("STATE_NoEmergencyClaim");
      });

      it("should allow rewards to be claimable", async () => {
        const { staking, stakingUser, tokenDist, user } = ctx;

        // Wait to ensure that depositor not immediately depositing
        await increaseTime(oneWeekSec / 2);

        await stakingUser.stake(ether("10000"), lockTwoWeeks);

        const balanceBefore = await tokenDist.balanceOf(user.address);

        // Move forward one week - rewards should be emitted
        await increaseTime(oneWeekSec * 2);

        await staking.emergencyStop(true);
        await stakingUser.emergencyUnstake();

        // Try to claim rewards normally
        await expect(stakingUser.claim(0)).to.be.revertedWith("STATE_ContractKilled");
        await expect(stakingUser.claimAll()).to.be.revertedWith("STATE_ContractKilled");

        // Try to claim rewards thru emergency
        const tx = await stakingUser.emergencyClaim();
        const receipt = await tx.wait();

        const claimEvent = receipt.events?.find(e => e.event === "EmergencyClaim");

        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user.address);
        expect(claimEvent?.args?.[1]).to.equal(rewardPerEpoch);

        const balanceAfter = await tokenDist.balanceOf(user.address);

        expectRoundedEqual(balanceAfter.sub(balanceBefore), rewardPerEpoch);

        const contractBalanceAfter = await tokenDist.balanceOf(staking.address);
        expectRoundedEqual(contractBalanceAfter, 0);
      });

      it("should allow rewards to be claimable, up until the moment of emergencyStop", async () => {
        const { staking, stakingUser, tokenDist, user } = ctx;

        await stakingUser.stake(ether("10000"), lockTwoWeeks);

        const balanceBefore = await tokenDist.balanceOf(user.address);

        // Move forward 1/2 week - 1/2 rewards should be emitted
        await increaseTime(oneWeekSec / 2);

        await staking.emergencyStop(true);
        await stakingUser.emergencyUnstake();

        // Try to claim rewards normally
        await expect(stakingUser.claim(0)).to.be.revertedWith("STATE_ContractKilled");
        await expect(stakingUser.claimAll()).to.be.revertedWith("STATE_ContractKilled");

        // Try to claim rewards thru emergency
        const tx = await stakingUser.emergencyClaim();
        const receipt = await tx.wait();

        const claimEvent = receipt.events?.find(e => e.event === "EmergencyClaim");

        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user.address);
        expectRoundedEqual(claimEvent?.args?.[1], rewardPerEpoch.div(2)); // now half, since program was stopped halfway through

        const balanceAfter = await tokenDist.balanceOf(user.address);

        expectRoundedEqual(balanceAfter.sub(balanceBefore), rewardPerEpoch.div(2));

        const contractBalanceAfter = await tokenDist.balanceOf(staking.address);
        expectRoundedEqual(contractBalanceAfter, 0);
      });
    });

    describe("emergencyClaim", () => {
      const rewardPerEpoch = ether(oneWeekSec.toString());

      beforeEach(async () => {
        await ctx.staking.setRewardsDuration(oneWeekSec);
        await ctx.staking.notifyRewardAmount(rewardPerEpoch);
      });

      it("should revert if the staking program has not been ended", async () => {
        const { stakingUser } = ctx;

        await expect(stakingUser.emergencyClaim()).to.be.revertedWith("STATE_NoEmergencyUnstake");
      });

      it("should revert if the contract stopped with claim disabled", async () => {
        const { staking, stakingUser } = ctx;

        await staking.emergencyStop(false);
        await expect(stakingUser.emergencyClaim()).to.be.revertedWith("STATE_NoEmergencyClaim");
      });

      it("should distribute all unclaimed rewards", async () => {
        const { staking, stakingUser, tokenDist, user } = ctx;

        // Multiple stakes - claim should harvest all
        await stakingUser.stake(ether("10000"), lockDay);
        await stakingUser.stake(ether("10000"), lockTwoWeeks);

        const balanceBefore = await tokenDist.balanceOf(user.address);

        // Move forward one week - rewards should be emitted
        await increaseTime(oneWeekSec * 2);

        // Unbond to update reward
        await stakingUser.unbondAll();

        await staking.emergencyStop(true);

        // Try to claim rewards thru emergency
        const tx = await stakingUser.emergencyClaim();
        const receipt = await tx.wait();

        const claimEvent = receipt.events?.find(e => e.event === "EmergencyClaim");

        // Need looser precision on claim amounts because in emergency situations
        // we do not recalculate rewards
        expect(claimEvent).to.not.be.undefined;
        expect(claimEvent?.args?.[0]).to.equal(user.address);
        expectRoundedEqual(claimEvent?.args?.[1], rewardPerEpoch, 5);

        const balanceAfter = await tokenDist.balanceOf(user.address);

        expectRoundedEqual(balanceAfter.sub(balanceBefore), rewardPerEpoch, 5);
      });
    });
  });

  describe("Admin Operations", () => {
    describe("notifyRewardAmount", () => {
      let distributor: SignerWithAddress;
      let stakingDist: CellarStaking;

      beforeEach(async () => {
        const totalRewards = ether(String(20_000_000));

        distributor = ctx.admin;
        await ctx.tokenDist.mint(distributor.address, totalRewards);

        stakingDist = await ctx.connectUser(distributor);
      });

      it("should revert if caller is not the owner", async () => {
        const { stakingUser } = ctx;

        await expect(stakingUser.notifyRewardAmount(ether("100"))).to.be.revertedWith(
          "Ownable: caller is not the owner",
        );
      });

      it("should revert if the staking contract is not funded with enough tokens", async () => {
        // Schedule very large program
        const largeAmount = ether("1").mul(BigNumber.from(10).pow(50));

        await expect(stakingDist.notifyRewardAmount(largeAmount)).to.be.revertedWith("STATE_RewardsNotFunded");
      });

      it("should revert if the the reward is less than one base unit per second", async () => {
        await expect(stakingDist.notifyRewardAmount(1)).to.be.revertedWith("USR_ZeroRewardsPerEpoch");
      });

      it("should revert if the the reward amount may cause overflow", async () => {
        const { tokenDist, staking } = ctx;

        const largeAmount = ether("1").mul(BigNumber.from(10).pow(50));
        await tokenDist.mint(staking.address, largeAmount);

        await expect(stakingDist.notifyRewardAmount(largeAmount)).to.be.revertedWith("USR_RewardTooLarge");
      });

      it("should schedule new rewards", async () => {
        const { tokenDist, stakingUser } = ctx;

        // Equates to one unit per second distributed
        const rewards = ether(oneMonthSec.toString());
        const balanceBefore = await tokenDist.balanceOf(distributor.address);

        await tokenDist.connect(distributor).transfer(stakingDist.address, rewards);
        let tx = await stakingDist.notifyRewardAmount(rewards);
        await tx.wait();

        // No funding event emitted, but should be on first stake
        expect(await stakingDist.rewardsReady()).to.equal(rewards);

        tx = await stakingUser.stake(ether("1"), lockDay);
        const receipt = await tx.wait();
        const latestBlock = await ethers.provider.getBlock("latest");

        const fundingEvent = receipt.events?.find(e => e.event === "Funding");

        expect(fundingEvent).to.not.be.undefined;
        expect(fundingEvent?.args?.[0]).to.equal(rewards);
        expect(fundingEvent?.args?.[1]).to.equal(latestBlock.timestamp + oneMonthSec);

        // Check reward rate, end timestamp, and balances
        expect(await stakingDist.rewardRate()).to.equal(ether("1"));
        expect(await stakingDist.endTimestamp()).to.equal(latestBlock.timestamp + oneMonthSec);
        expect(await tokenDist.balanceOf(stakingDist.address)).to.equal(initialTokenAmount.add(rewards));

        const balanceAfter = await tokenDist.balanceOf(distributor.address);

        expect(balanceBefore.sub(balanceAfter)).to.equal(rewards);
      });

      it("should revert if the staking contract is not funded with enough tokens, counting an existing schedule", async () => {
        const { stakingUser } = ctx;
        // Call notify reward amount once
        await stakingDist.notifyRewardAmount(initialTokenAmount);

        // Stake to start the schedule
        await stakingUser.stake(ether("1"), lockDay);

        // Schedule initialTokenAmount / 2 new rewards. Should fail because in total we need 3 * initialTokenAmount / 2 rewards
        await expect(
          stakingDist.notifyRewardAmount(initialTokenAmount.div(2))
        ).to.be.revertedWith("STATE_RewardsNotFunded");
      });

      it("should update and extend existing schedule", async () => {
        const { tokenDist, stakingUser } = ctx;

        // Equates to one unit per second distributed
        const rewards = ether(oneMonthSec.toString());
        const balanceBefore = await tokenDist.balanceOf(distributor.address);
        await tokenDist.connect(distributor).transfer(stakingDist.address, rewards);

        await expect(stakingDist.notifyRewardAmount(rewards)).to.not.be.reverted;

        await stakingUser.stake(ether("10000"), lockDay);
        let latestBlock = await ethers.provider.getBlock("latest");

        expect(await stakingDist.rewardRate()).to.equal(ether("1"));
        expect(await stakingDist.endTimestamp()).to.equal(latestBlock.timestamp + oneMonthSec);
        expect(await tokenDist.balanceOf(stakingDist.address)).to.equal(initialTokenAmount.add(rewards));

        // Run halfway through, then start a new rewards period
        await increaseTime(oneMonthSec / 2);

        // Have someone claim
        await stakingUser.claimAll();

        // Transfer in and notify more rewards
        await tokenDist.connect(distributor).transfer(stakingDist.address, rewards);
        await expect(stakingDist.notifyRewardAmount(rewards)).to.not.be.reverted;
        latestBlock = await ethers.provider.getBlock("latest");

        // Reward rate should be 1.5x as as large, since leftover 0.5 gets carried
        expectRoundedEqual(await stakingDist.rewardRate(), ether("1.5"));

        // Period should be reset
        expect(await stakingDist.endTimestamp()).to.equal(latestBlock.timestamp + oneMonthSec);

        expectRoundedEqual(
          await tokenDist.balanceOf(stakingDist.address),
          initialTokenAmount.add(rewards.div(2).mul(3)),
        );

        const balanceAfter = await tokenDist.balanceOf(distributor.address);

        // Funded twice
        expect(balanceBefore.sub(balanceAfter)).to.equal(rewards.mul(2));
      });
    });

    describe("setRewardsDuration", () => {
      it("should revert if caller is not the owner", async () => {
        const { stakingUser } = ctx;

        await expect(stakingUser.setRewardsDuration(oneWeekSec)).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("should update the reward epoch duration", async () => {
        const { staking } = ctx;

        const currentEpochDuration = await staking.currentEpochDuration();
        expect(await staking.nextEpochDuration()).to.equal(oneMonthSec);

        await expect(staking.setRewardsDuration(oneWeekSec))
          .to.emit(staking, "EpochDurationChange")
          .withArgs(oneWeekSec);

        expect(await staking.nextEpochDuration()).to.equal(oneWeekSec);
        expect(await staking.currentEpochDuration()).to.equal(currentEpochDuration);
      });
    });

    describe("setMinimumDeposit", () => {
      it("should revert if caller is not the owner", async () => {
        const { stakingUser } = ctx;

        await expect(stakingUser.setMinimumDeposit(ether("1"))).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("should set a new minimum staking deposit and immediately enforce it", async () => {
        const { staking, stakingUser } = ctx;

        await staking.notifyRewardAmount(oneMonthSec);

        expect(await staking.minimumDeposit()).to.equal(0);
        await expect(stakingUser.stake(ether("1"), lockDay)).to.not.be.reverted;

        await expect(staking.setMinimumDeposit(ether("10"))).to.not.be.reverted;

        expect(await staking.minimumDeposit()).to.equal(ether("10"));
        await expect(stakingUser.stake(ether("1"), lockDay)).to.be.revertedWith("USR_MinimumDeposit");
      });
    });

    describe("setPaused", () => {
      it("should revert if caller is not the owner", async () => {
        const { stakingUser } = ctx;

        await expect(stakingUser.setPaused(true)).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("should pause the contract", async () => {
        const { staking, stakingUser } = ctx;

        await expect(staking.setPaused(true)).to.not.be.reverted;
        expect(await staking.paused()).to.equal(true);

        // Make sure everything paused
        await expect(stakingUser.stake(ether("10"), lockDay)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unbond(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unbondAll()).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbonding(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbondingAll()).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbonding(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbondingAll()).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unstake(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unstakeAll()).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.claim(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.claimAll()).to.be.revertedWith("STATE_ContractPaused");
      });

      it("should unpause the contract", async () => {
        const { staking, stakingUser } = ctx;

        await expect(staking.setPaused(true)).to.not.be.reverted;
        expect(await staking.paused()).to.equal(true);

        // Make sure everything paused
        await expect(stakingUser.stake(ether("10"), lockDay)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unbond(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unbondAll()).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbonding(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbondingAll()).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbonding(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbondingAll()).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unstake(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unstakeAll()).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.claim(0)).to.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.claimAll()).to.be.revertedWith("STATE_ContractPaused");

        // Now unpause
        await expect(staking.setPaused(false)).to.not.be.reverted;
        expect(await staking.paused()).to.equal(false);

        // Make sure everything allowed (may revert for other reasons)
        await expect(stakingUser.stake(ether("10"), lockDay)).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unbond(0)).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unbondAll()).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbonding(0)).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbondingAll()).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbonding(0)).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.cancelUnbondingAll()).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unstake(0)).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.unstakeAll()).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.claim(0)).to.not.be.revertedWith("STATE_ContractPaused");
        await expect(stakingUser.claimAll()).to.not.be.revertedWith("STATE_ContractPaused");
      });
    });

    describe("emergencyStop", () => {
      it("should revert if caller is not the owner", async () => {
        const { stakingUser } = ctx;

        await expect(stakingUser.emergencyStop(false)).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("should end the contract while making rewards claimable", async () => {
        const { staking, stakingUser } = ctx;

        await expect(staking.emergencyStop(true))
          .to.emit(staking, "EmergencyStop")
          .withArgs(await staking.signer.getAddress(), true);

        expect(await staking.ended()).to.equal(true);
        expect(await staking.claimable()).to.equal(true);

        await expect(stakingUser.emergencyUnstake()).to.not.be.revertedWith("STATE_NoEmergencyUnstake");
        await expect(stakingUser.emergencyClaim())
          .to.not.be.revertedWith("STATE_NoEmergencyClaim")
          .and.to.not.be.revertedWith("STATE_NoEmergencyUnstake");
      });

      it("should end the contract and return distribution tokens if rewards are not claimable", async () => {
        const { admin, staking, stakingUser, tokenDist } = ctx;

        // Make sure contract only has oneMonthSecTokens
        const originalBalance = await tokenDist.balanceOf(admin.address);
        await tokenDist.connect(admin).transfer(staking.address, oneMonthSec);
        await staking.notifyRewardAmount(oneMonthSec);
        const balanceAfterFunding = await tokenDist.balanceOf(admin.address);

        expect(originalBalance.sub(balanceAfterFunding)).to.equal(oneMonthSec);

        await stakingUser.stake(ether("10"), lockDay);

        await increaseTime(oneWeekSec);

        await expect(staking.emergencyStop(false))
          .to.emit(staking, "EmergencyStop")
          .withArgs(await staking.signer.getAddress(), false);

        expect(await staking.ended()).to.equal(true);
        expect(await staking.claimable()).to.equal(false);

        // Should get all coins back, since stakingUser never claimed
        const balanceAfterStop = await tokenDist.balanceOf(admin.address);
        expect(originalBalance).to.equal(balanceAfterStop.sub(initialTokenAmount));

        await expect(stakingUser.emergencyUnstake()).to.not.be.revertedWith("STATE_NoEmergencyUnstake");
        await expect(stakingUser.emergencyClaim()).to.be.revertedWith("STATE_NoEmergencyClaim");
      });

      it("should revert if called more than once", async () => {
        const { staking } = ctx;

        await expect(staking.emergencyStop(true))
          .to.emit(staking, "EmergencyStop")
          .withArgs(await staking.signer.getAddress(), true);

        // Try to stop again
        await expect(staking.emergencyStop(true)).to.be.revertedWith("STATE_AlreadyShutdown");
      });
    });
  });

  describe("State Information", () => {
    describe("latestRewardsTimestamp", () => {
      let latestBlock: Block;

      beforeEach(async () => {
        await ctx.staking.notifyRewardAmount(oneMonthSec);
        await ctx.stakingUser.stake(ether("1"), lockDay);
        latestBlock = await ethers.provider.getBlock("latest");
      });

      it("should report the latest block timestamp if rewards are ongoing", async () => {
        const { staking } = ctx;

        expect(await staking.latestRewardsTimestamp()).to.equal(latestBlock.timestamp);
      });

      it("should report the ending timestamp of the rewards period if the period has ended", async () => {
        const { staking } = ctx;

        // Move past rewards end
        await increaseTime(latestBlock.timestamp + oneMonthSec * 2);

        expect(await staking.latestRewardsTimestamp()).to.equal(latestBlock.timestamp + oneMonthSec);
      });
    });

    describe("rewardPerToken", () => {
      let latestBlock: Block;
      let stakeAmount: BigNumber;

      beforeEach(async () => {
        stakeAmount = ether(oneMonthSec.toString());

        await ctx.staking.notifyRewardAmount(stakeAmount);
        latestBlock = await ethers.provider.getBlock("latest");
      });

      it("reports the latest rewards per deposited token", async () => {
        const { stakingUser } = ctx;
        // Deposit 50% of total rewards - will be equal after boost
        await stakingUser.stake(BigNumber.from(oneMonthSec).div(2), lockTwoWeeks);

        // Move halfway through
        await setNextBlockTimestamp(latestBlock.timestamp + oneMonthSec / 2);

        // Half rewards distributed, which means that .5 tokens dist per deposited token
        // Need to divide by one ether since zeroes are added for precision
        const rewardPerToken = (await stakingUser.rewardPerToken())[0].div(ether("1"));
        expectRoundedEqual(rewardPerToken, ether(".5"));
      });

      it("reports the last calculated rewards per token if there are no deposits", async () => {
        const { stakingUser } = ctx;
        // Deposit 71.43% of total rewards - will be equal after boost
        await stakingUser.stake(BigNumber.from(oneMonthSec).div(10000).mul(7143), lockWeek);
        await stakingUser.unbondAll();

        // Move halfway through
        await setNextBlockTimestamp(latestBlock.timestamp + oneMonthSec / 2);
        await stakingUser.unstake(0);

        // Get reward per tokenStored
        const [rewardPerToken] = await stakingUser.rewardPerToken();
        const rewardPerTokenStored = await stakingUser.rewardPerTokenStored();

        expect(rewardPerToken).to.equal(rewardPerTokenStored);

        // Move forward
        await increaseTime(oneMonthSec);

        // Check again
        const [newRewardPerToken] = await stakingUser.rewardPerToken();
        const newRewardPerTokenStored = await stakingUser.rewardPerTokenStored();

        expect(rewardPerTokenStored).to.equal(newRewardPerTokenStored);
        expect(newRewardPerToken).to.equal(newRewardPerTokenStored);
      });
    });

    describe("stake information", () => {
      const rewardPerEpoch = ether(oneWeekSec.toString());
      const stakeAmount = ether("1000");

      beforeEach(async () => {
        await ctx.staking.setRewardsDuration(oneWeekSec);
        await ctx.staking.notifyRewardAmount(rewardPerEpoch);

        await ctx.stakingUser.stake(stakeAmount, lockDay);
        await ctx.stakingUser.stake(stakeAmount.mul(2), lockWeek);
        await ctx.stakingUser.stake(stakeAmount.mul(3), lockTwoWeeks);
      });

      it("should report the details of a single stake", async () => {
        const { stakingUser, user } = ctx;

        const stake1 = await stakingUser.stakes(user.address, 0);
        let boostMultiplier = stakeAmount.mul(await stakingUser.SHORT_BOOST()).div(ether("1"));
        let expectedAmountWithBoost = stakeAmount.add(boostMultiplier);

        expect(stake1.amount).to.equal(stakeAmount);
        expect(stake1.amountWithBoost).to.equal(expectedAmountWithBoost);
        expect(stake1.rewards).to.equal(0);
        expect(stake1.unbondTimestamp).to.equal(0);
        expect(stake1.lock).to.equal(lockDay);

        const stake2 = await stakingUser.stakes(user.address, 1);
        boostMultiplier = stakeAmount
          .mul(2)
          .mul(await stakingUser.MEDIUM_BOOST())
          .div(ether("1"));
        expectedAmountWithBoost = stakeAmount.mul(2).add(boostMultiplier);

        expect(stake2.amount).to.equal(stakeAmount.mul(2));
        expect(stake2.amountWithBoost).to.equal(expectedAmountWithBoost);
        expect(stake2.rewards).to.equal(0);
        expect(stake2.unbondTimestamp).to.equal(0);
        expect(stake2.lock).to.equal(lockWeek);

        const stake3 = await stakingUser.stakes(user.address, 2);
        boostMultiplier = stakeAmount
          .mul(3)
          .mul(await stakingUser.LONG_BOOST())
          .div(ether("1"));
        expectedAmountWithBoost = stakeAmount.mul(3).add(boostMultiplier);

        expect(stake3.amount).to.equal(stakeAmount.mul(3));
        expect(stake3.amountWithBoost).to.equal(expectedAmountWithBoost);
        expect(stake3.rewards).to.equal(0);
        expect(stake3.unbondTimestamp).to.equal(0);
        expect(stake3.lock).to.equal(lockTwoWeeks);
      });

      it("should report all a user's stakes", async () => {
        const { stakingUser, user } = ctx;

        const userStakes = await stakingUser.getUserStakes(user.address);
        expect(userStakes.length).to.equal(3);
      });
    });
  });

  describe("Advanced Scenarios", () => {
    it("scenario 1", async () => {
      const { staking, tokenDist } = ctx;

      const { actions, rewards } = setupAdvancedScenario1(ctx);

      await fundAndApprove(ctx);
      await runScenario(ctx, actions);

      // Now check all expected rewards and user balance
      // Shuffle to ensure that order doesn't matter
      const shuffledRewards = shuffle(rewards);
      // const shuffledRewards = rewards;
      for (const reward of shuffledRewards) {
        const { signer, expectedReward } = reward;
        const preclaimBalance = await tokenDist.balanceOf(signer.address);

        await claimWithRoundedRewardCheck(staking, signer, expectedReward);
        const postclaimBalance = await tokenDist.balanceOf(signer.address);

        expectRoundedEqual(postclaimBalance.sub(preclaimBalance), expectedReward);

        // Withdraw funds to make sure we can
        await expect(staking.connect(signer).unbondAll()).to.not.be.reverted;

        // Mine a block to wind clock
        await ethers.provider.send("evm_increaseTime", [10]);
      }

      // Make sure all claims return 0
      for (const reward of shuffledRewards) {
        // Make sure another claim gives 0
        await claimWithRoundedRewardCheck(staking, reward.signer, 0);
      }

      // Make sure we can withdraw
      await increaseTime(oneWeekSec * 2);

      for (const reward of shuffledRewards) {
        await expect(staking.connect(reward.signer).unstakeAll()).to.not.be.reverted;
      }
    });

    it("scenario 2", async () => {
      const { staking, tokenDist } = ctx;

      const { actions, rewards } = setupAdvancedScenario2(ctx);

      await fundAndApprove(ctx);
      await runScenario(ctx, actions);

      // Now check all expected rewards and user balance
      // Shuffle to ensure that order doesn't matter
      const shuffledRewards = shuffle(rewards);
      // const shuffledRewards = rewards;
      for (const reward of shuffledRewards) {
        const { signer, expectedReward } = reward;
        const preclaimBalance = await tokenDist.balanceOf(signer.address);

        await claimWithRoundedRewardCheck(staking, signer, expectedReward);
        const postclaimBalance = await tokenDist.balanceOf(signer.address);

        expectRoundedEqual(postclaimBalance.sub(preclaimBalance), expectedReward);

        // Withdraw funds to make sure we can
        await expect(staking.connect(signer).unbondAll()).to.not.be.reverted;

        // Mine a block to wind clock
        await ethers.provider.send("evm_increaseTime", [10]);
      }

      // Make sure all claims return 0
      for (const reward of shuffledRewards) {
        // Make sure another claim gives 0
        await claimWithRoundedRewardCheck(staking, reward.signer, 0);
      }

      // Make sure we can withdraw
      await increaseTime(oneWeekSec * 2);

      for (const reward of shuffledRewards) {
        await expect(staking.connect(reward.signer).unstakeAll()).to.not.be.reverted;
      }
    });

    it("scenario 3", async () => {
      const { staking, tokenDist } = ctx;

      const { actions, rewards } = setupAdvancedScenario3(ctx);

      await fundAndApprove(ctx);

      const preclaimBalances: { [user: string]: BigNumberish } = {};
      for (const { signer } of rewards) {
        preclaimBalances[signer.address] = await tokenDist.balanceOf(signer.address);
      }

      const claims = await runScenario(ctx, actions);

      // Now check all expected rewards and user balance
      // Shuffle to ensure that order doesn't matter
      const shuffledRewards = shuffle(rewards);
      // const shuffledRewards = rewards;
      for (const reward of shuffledRewards) {
        const { signer, expectedReward } = reward;
        const preclaimBalance = preclaimBalances[signer.address];

        // Adjust if midstream claims/withdraws have been made
        let adjustedExpectedReward = ethers.BigNumber.from(expectedReward).sub(claims[signer.address] || 0);
        if (adjustedExpectedReward.lt(expectedReward.div(100))) {
          // Round to 0 if less than 1% off
          adjustedExpectedReward = ethers.BigNumber.from(0);
        }

        await claimWithRoundedRewardCheck(staking, signer, adjustedExpectedReward);
        const postclaimBalance = await tokenDist.balanceOf(signer.address);

        expectRoundedEqual(postclaimBalance.sub(preclaimBalance), expectedReward);

        // Withdraw funds to make sure we can
        await expect(staking.connect(signer).unbondAll()).to.not.be.reverted;

        // Mine a block to wind clock
        await ethers.provider.send("evm_increaseTime", [10]);
      }

      // Make sure all claims return 0
      for (const reward of shuffledRewards) {
        // Make sure another claim gives 0
        await claimWithRoundedRewardCheck(staking, reward.signer, 0);
      }

      // Make sure we can withdraw
      await increaseTime(oneWeekSec * 2);

      for (const reward of shuffledRewards) {
        await expect(staking.connect(reward.signer).unstakeAll()).to.not.be.reverted;
      }
    });

    it("scenario 4", async () => {
      const { staking, tokenDist } = ctx;

      const { actions, rewards } = setupAdvancedScenario4(ctx);

      await fundAndApprove(ctx);

      const preclaimBalances: { [user: string]: BigNumberish } = {};
      for (const { signer } of rewards) {
        preclaimBalances[signer.address] = await tokenDist.balanceOf(signer.address);
      }

      const claims = await runScenario(ctx, actions);

      // Now check all expected rewards and user balance
      // Shuffle to ensure that order doesn't matter
      const shuffledRewards = shuffle(rewards);
      // const shuffledRewards = rewards;
      for (const reward of shuffledRewards) {
        const { signer, expectedReward } = reward;
        const preclaimBalance = preclaimBalances[signer.address];

        // Adjust if midstream claims/withdraws have been made
        let adjustedExpectedReward = ethers.BigNumber.from(expectedReward).sub(claims[signer.address] || 0);
        if (adjustedExpectedReward.lt(expectedReward.div(100))) {
          // Round to 0 if less than 1% off
          adjustedExpectedReward = ethers.BigNumber.from(0);
        }

        await claimWithRoundedRewardCheck(staking, signer, adjustedExpectedReward);
        const postclaimBalance = await tokenDist.balanceOf(signer.address);

        expectRoundedEqual(postclaimBalance.sub(preclaimBalance), expectedReward);

        // Withdraw funds to make sure we can
        await expect(staking.connect(signer).unbondAll()).to.not.be.reverted;

        // Mine a block to wind clock
        await ethers.provider.send("evm_increaseTime", [10]);
      }

      // Make sure all claims return 0
      for (const reward of shuffledRewards) {
        // Make sure another claim gives 0
        await claimWithRoundedRewardCheck(staking, reward.signer, 0);
      }

      // Make sure we can withdraw
      await increaseTime(oneWeekSec * 2);

      for (const reward of shuffledRewards) {
        await expect(staking.connect(reward.signer).unstakeAll()).to.not.be.reverted;
      }
    });

    it("scenario 5", async () => {
      const { staking, tokenDist } = ctx;

      const { actions, rewards } = setupAdvancedScenario4(ctx);

      await fundAndApprove(ctx);

      const preclaimBalances: { [user: string]: BigNumberish } = {};
      for (const { signer } of rewards) {
        preclaimBalances[signer.address] = await tokenDist.balanceOf(signer.address);
      }

      const claims = await runScenario(ctx, actions);

      // Now check all expected rewards and user balance
      // Shuffle to ensure that order doesn't matter
      const shuffledRewards = shuffle(rewards);
      // const shuffledRewards = rewards;
      for (const reward of shuffledRewards) {
        const { signer, expectedReward } = reward;
        const preclaimBalance = preclaimBalances[signer.address];

        // Adjust if midstream claims/withdraws have been made
        let adjustedExpectedReward = ethers.BigNumber.from(expectedReward).sub(claims[signer.address] || 0);
        if (adjustedExpectedReward.lt(expectedReward.div(100))) {
          // Round to 0 if less than 1% off
          adjustedExpectedReward = ethers.BigNumber.from(0);
        }

        await claimWithRoundedRewardCheck(staking, signer, adjustedExpectedReward);
        const postclaimBalance = await tokenDist.balanceOf(signer.address);

        expectRoundedEqual(postclaimBalance.sub(preclaimBalance), expectedReward);

        // Withdraw funds to make sure we can
        await expect(staking.connect(signer).unbondAll()).to.not.be.reverted;

        // Mine a block to wind clock
        await ethers.provider.send("evm_increaseTime", [10]);
      }

      // Make sure all claims return 0
      for (const reward of shuffledRewards) {
        // Make sure another claim gives 0
        await claimWithRoundedRewardCheck(staking, reward.signer, 0);
      }

      // Make sure we can withdraw
      await increaseTime(oneWeekSec * 2);

      for (const reward of shuffledRewards) {
        await expect(staking.connect(reward.signer).unstakeAll()).to.not.be.reverted;
      }
    });
  });

  describe("Corner Cases", () => {
    it("Old stakers should not be able to claim rewards of the new reward cycle", async () => {
      const { staking, stakingUser, user, tokenDist } = ctx;
      const min = ether("1");
      await staking.setMinimumDeposit(min);

      // Reward Cycle 1
      await ctx.staking.notifyRewardAmount(ether(oneMonthSec.toString()));
      await stakingUser.stake(ether("1"), 0);
      await increaseTime(oneMonthSec * 2);

      // shortTermboost : 0
      // lock: 0
      // staked: 1 ether
      // total: 1 ether
      // total rewards: 2592000
      // epochDuration: 2592000
      // rewardRate: 1
      // timePassed: 2592000*2

      await stakingUser.claim(0);
      expectRoundedEqual(await tokenDist.balanceOf(user.address), ether(oneMonthSec.toString()));

      // Reward Cycle 2
      await ctx.staking.notifyRewardAmount(ether(oneMonthSec.toString()));
      await stakingUser.claim(0);
      expectRoundedEqual(await tokenDist.balanceOf(user.address), ether(oneMonthSec.toString()));
    });
  })
});
