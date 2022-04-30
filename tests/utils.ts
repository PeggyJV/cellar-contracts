import hre from "hardhat";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Artifact } from "hardhat/types";
import { Contract, Signer, BigNumberish, ContractTransaction } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import type { CellarStaking } from "../src/types/CellarStaking";
import type { MockERC20 } from "../src/types/MockERC20";
import { Test } from "mocha";

const { deployContract } = hre.waffle;

export const ether = ethers.utils.parseEther;

const oneDaySec = 60 * 60 * 24;
const oneWeekSec = oneDaySec * 7;
const oneMonthSec = oneDaySec * 30;

const lockDay = 0;
const lockWeek = 1;
const lockTwoWeeks = 2;

const programStart = Math.floor(Date.now() / 1000) + 10_000_000;
const programEnd = programStart + oneMonthSec;
const TOTAL_REWARDS = ether(oneMonthSec.toString());

export interface TestContext {
  admin: SignerWithAddress;
  connectUser: (signer: SignerWithAddress) => Promise<CellarStaking>;
  signers: SignerWithAddress[];
  staking: CellarStaking;
  stakingUser: CellarStaking;
  tokenDist: MockERC20;
  tokenStake: MockERC20;
  user: SignerWithAddress;
}

export interface Action {
  timestamp: number;
  actions: ActionInfo[];
}

export interface ActionInfo {
  signer: SignerWithAddress;
  amount: BigNumberish;
  action: "deposit" | "withdraw" | "unbond" | "claim" | "cancelUnbonding" | "notify";
  lock?: 0 | 1 | 2;
}

export interface RewardInfo {
  signer: SignerWithAddress;
  expectedReward: BigNumberish;
}
export interface ScenarioInfo {
  actions: Action[];
  rewards: RewardInfo[];
}

/**
 * Deploy a contract with the given artifact name
 * Will be deployed by the given deployer address with the given params
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function deploy<T extends Contract>(contractName: string, deployer: Signer, params: any[]): Promise<T> {
  const artifact: Artifact = await hre.artifacts.readArtifact(contractName);
  return <T>await deployContract(deployer, artifact, params);
}

export function rand(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// TIME
export async function increaseTime(seconds: number): Promise<void> {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

export async function setNextBlockTimestamp(epoch: number): Promise<void> {
  await ethers.provider.send("evm_setNextBlockTimestamp", [epoch]);
  await ethers.provider.send("evm_mine", []);
}

export async function unbondUnstake(staking: CellarStaking, user: SignerWithAddress, depositId: number): Promise<void> {
  await staking.unbond(depositId);
  const stake = await staking.stakes(user.address, depositId);
  const unbondTimestamp = stake.unbondTimestamp;

  await setNextBlockTimestamp(unbondTimestamp + 1);
  await staking.unstake(depositId);
}

export const expectRoundedEqual = (num: BigNumberish, target: BigNumberish, pctWithin = 1): void => {
  num = ethers.BigNumber.from(num);
  target = ethers.BigNumber.from(target);

  // Tolerable precision is 0.1%. Precision is lost in the magic mine in both
  // calculating NFT reward boosts and timing per second
  const precision = 100;
  const denom = ether("1").div(precision);

  if (target.eq(0)) {
    expect(num).to.be.lte(ether("1"));
  } else if (num.eq(0)) {
    expect(target).to.be.lte(ether("1"));
  } else {
    // Expect it to be less than 2% diff
    const lowerBound = target.div(denom).mul(denom.div(100).mul(100 - pctWithin));
    const upperBound = target.div(denom).mul(denom.div(100).mul(100 + pctWithin));

    expect(num).to.be.gte(lowerBound);
    expect(num).to.be.lte(upperBound);
  }
};

export const claimWithRoundedRewardCheck = async (
  staking: CellarStaking,
  user: SignerWithAddress,
  expectedReward: BigNumberish,
): Promise<ContractTransaction> => {
  const claimTx = await staking.connect(user).claimAll();
  const receipt = await claimTx.wait();

  // Cannot use expect matchers because of rounded equal comparison
  const claimEvents = receipt.events?.filter(e => e.event === "Claim");

  let reward = ethers.BigNumber.from(0);
  for (const event of claimEvents!) {
    expect(event).to.not.be.undefined;
    expect(event?.args?.[0]).to.eq(user.address);

    reward = reward.add(event?.args?.[2]);
  }

  expectRoundedEqual(reward, expectedReward);

  return claimTx;
};

export const fundAndApprove = async (ctx: TestContext): Promise<void> => {
  const { signers, tokenStake, staking } = ctx;

  const [...users] = signers.slice(1, 5);

  const stakerFunding = users.map(u => tokenStake.mint(u.address, ether("100000")));
  const stakerApprove = users.map(u => tokenStake.connect(u).approve(staking.address, ether("100000")));
  await Promise.all(stakerFunding.concat(stakerApprove));
};

export const setupAdvancedScenario1 = (ctx: TestContext): ScenarioInfo => {
  // Advanced Scenario 1:
  // (Different stake times, all unbond + unstake after program end, same locks)
  //
  // Staker 1 Deposits N at 0 with one day lock
  // Staker 2 Deposits N/3 at 0.25 with one day lock
  // Staker 3 Deposits 2N/3 at 0.5 with one day lock
  // Staker 4 Deposits 2N at 0.75 with one day lock
  //
  //            Staker 1 %        Staker 2 %      Staker 3 %     Staker 4 %
  // At T = 0:    100                 0               0               0
  // At T = 0.25:  75                25               0               0
  // At T = 0.5:   50             16.67           33.33               0
  // At T = 0.75:  25              8.33           16.67              50
  // Totals:      62.5             12.5            12.5             12.5
  // Total Deposits:

  const {
    signers: [, user1, user2, user3, user4],
  } = ctx;

  const baseAmount = ether("100");
  const totalTime = oneMonthSec;
  const totalRewardsBase = TOTAL_REWARDS.div(10000);

  const actions: Action[] = [
    {
      timestamp: programStart + 5,
      actions: [
        {
          signer: user1,
          amount: baseAmount,
          action: "deposit",
          lock: lockDay,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.25,
      actions: [
        {
          signer: user2,
          amount: baseAmount.div(3),
          action: "deposit",
          lock: lockDay,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.5,
      actions: [
        {
          signer: user3,
          amount: baseAmount.div(3).mul(2),
          action: "deposit",
          lock: lockDay,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.75,
      actions: [
        {
          signer: user4,
          amount: baseAmount.mul(2),
          action: "deposit",
          lock: lockDay,
        },
      ],
    },
  ];

  const rewards: RewardInfo[] = [
    {
      signer: user1,
      expectedReward: totalRewardsBase.mul(6250),
    },
    {
      signer: user2,
      expectedReward: totalRewardsBase.mul(1250),
    },
    {
      signer: user3,
      expectedReward: totalRewardsBase.mul(1250),
    },
    {
      signer: user4,
      expectedReward: totalRewardsBase.mul(1250),
    },
  ];

  return { actions, rewards };
};

export const setupAdvancedScenario2 = (ctx: TestContext): ScenarioInfo => {
  // Advanced Scenario 2:
  // (Different stake times, all unbond + unstake after program end, different locks)
  //
  // Staker 1 Deposits N at 0 with two week lock (v = 2N)
  // Staker 2 Deposits N/3 at 0.25 with one day lock (v = .3667N)
  // Staker 3 Deposits 2N/3 at 0.5 with one week lock (v = .9333N)
  // Staker 4 Deposits 2N at 0.75 with one day lock (v = 2.2N)
  //
  //            Staker 1 %        Staker 2 %      Staker 3 %     Staker 4 %
  // At T = 0:      100                 0               0               0
  // At T = 0.25:  84.5              15.5               0               0
  // At T = 0.5:   60.6             11.11           28.28               0
  // At T = 0.75: 36.36              6.67           16.97              40
  // Totals:      70.37              8.32           11.31              10
  // Total Deposits:

  const {
    signers: [, user1, user2, user3, user4],
  } = ctx;

  const baseAmount = ether("100");
  const totalTime = oneMonthSec;
  const totalRewardsBase = TOTAL_REWARDS.div(10000);

  const actions: Action[] = [
    {
      timestamp: programStart + 5,
      actions: [
        {
          signer: user1,
          amount: baseAmount,
          action: "deposit",
          lock: lockTwoWeeks,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.25,
      actions: [
        {
          signer: user2,
          amount: baseAmount.div(3),
          action: "deposit",
          lock: lockDay,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.5,
      actions: [
        {
          signer: user3,
          amount: baseAmount.div(3).mul(2),
          action: "deposit",
          lock: lockWeek,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.75,
      actions: [
        {
          signer: user4,
          amount: baseAmount.mul(2),
          action: "deposit",
          lock: lockDay,
        },
      ],
    },
  ];

  const rewards: RewardInfo[] = [
    {
      signer: user1,
      expectedReward: totalRewardsBase.mul(7037),
    },
    {
      signer: user2,
      expectedReward: totalRewardsBase.mul(832),
    },
    {
      signer: user3,
      expectedReward: totalRewardsBase.mul(1131),
    },
    {
      signer: user4,
      expectedReward: totalRewardsBase.mul(1000),
    },
  ];

  return { actions, rewards };
};

export const setupAdvancedScenario3 = (ctx: TestContext): ScenarioInfo => {
  // Advanced Scenario 3:
  // (Different stake times and locks, midstream unbonding and unstaking)
  //
  // Staker 1 Deposits N at 0 with two week lock (v = 2N)
  // Staker 2 Deposits 3N at 0 with one day lock (v = 3.3N)
  // Staker 3 Deposits 2N at 0.25 with one week lock (v = 2.8N)
  // Staker 2 Unbonds 3N at 0.25 (v = 3N)
  // Staker 4 Deposits 4N at 0.5 with two week lock (v = 8N)
  // Staker 3 Deposits 2N at 0.5 with one day lock (v = 2.2N)
  // Staker 2 Unstakes 3N at 0.75 (v = 0)
  // Staker 4 Unbonds 4N at 0.75 (v = 4N)
  //
  //            Staker 1 %        Staker 2 %      Staker 3 %     Staker 4 %
  // At T = 0:     37.73            62.26               0               0
  // At T = 0.25:  25.64            38.46            35.9               0
  // At T = 0.5:   11.11            16.67           27.78           44.44
  // At T = 0.75:  18.18                0           45.45           36.36
  // Totals:       23.17            29.35           27.28            20.2
  // Total Deposits:

  const {
    signers: [, user1, user2, user3, user4],
  } = ctx;

  const baseAmount = ether("100");
  const totalTime = oneMonthSec;
  const totalRewardsBase = TOTAL_REWARDS.div(10000);

  const actions: Action[] = [
    {
      timestamp: programStart + 5,
      actions: [
        {
          signer: user1,
          amount: baseAmount,
          action: "deposit",
          lock: lockTwoWeeks,
        },
        {
          signer: user2,
          amount: baseAmount.mul(3),
          action: "deposit",
          lock: lockDay,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.25,
      actions: [
        {
          signer: user3,
          amount: baseAmount.mul(2),
          action: "deposit",
          lock: lockWeek,
        },
        {
          signer: user2,
          amount: 0,
          action: "unbond",
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.5,
      actions: [
        {
          signer: user4,
          amount: baseAmount.mul(4),
          action: "deposit",
          lock: lockTwoWeeks,
        },
        {
          signer: user3,
          amount: baseAmount.mul(2),
          action: "deposit",
          lock: lockDay,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.75,
      actions: [
        {
          signer: user4,
          amount: 0,
          action: "unbond",
        },
        {
          signer: user2,
          amount: 0,
          action: "withdraw",
        },
      ],
    },
  ];

  const rewards: RewardInfo[] = [
    {
      signer: user1,
      expectedReward: totalRewardsBase.mul(2317),
    },
    {
      signer: user2,
      expectedReward: totalRewardsBase.mul(2935),
    },
    {
      signer: user3,
      expectedReward: totalRewardsBase.mul(2728),
    },
    {
      signer: user4,
      expectedReward: totalRewardsBase.mul(2020),
    },
  ];

  return { actions, rewards };
};

export const setupAdvancedScenario4 = (ctx: TestContext): ScenarioInfo => {
  // Advanced Scenario 4:
  // (Midstream unbonding and unstaking, re-staking, unbonding canceled)
  //
  // Staker 1 Deposits N at 0 with two week lock (v = 2N)
  // Staker 2 Deposits 3N at 0 with one day lock (v = 3.3N)
  // Staker 3 Deposits 2N at 0 with one week lock (v = 2.8N)
  // Staker 2 Unbonds 3N at 0.25 (v = 3N)
  // Staker 4 Deposits 4N at 0.25 with one week lock (v = 5.6N)
  // Staker 3 Deposits 2N at 0.25 with two week lock (v = 4N)
  // Staker 2 Unstakes 3N at 0.5 (v = 0)
  // Staker 4 Unbonds 4N at 0.5 (v = 4N)
  // Staker 2 Stakes 3N at 0.75 with one-day lock (v = 3.3N)
  // Staker 4 cancels unbonding at 0.75 (v = 5.6N)
  // Staker 3 Unbonds 4N at 0.75 (v = 4N)
  //
  //            Staker 1 %        Staker 2 %      Staker 3 %     Staker 4 %
  // At T = 0:     24.69            40.74           34.57               0
  // At T = 0.25:  11.49            17.24           39.08           32.18
  // At T = 0.5:   15.63                0           53.13           31.25
  // At T = 0.75:  13.42            22.15           26.85           37.58
  // Totals:       16.31            20.03           38.41           25.25

  const {
    signers: [, user1, user2, user3, user4],
  } = ctx;

  const baseAmount = ether("100");
  const totalTime = oneMonthSec;
  const totalRewardsBase = TOTAL_REWARDS.div(10000);

  const actions: Action[] = [
    {
      timestamp: programStart + 5,
      actions: [
        {
          signer: user1,
          amount: baseAmount,
          action: "deposit",
          lock: lockTwoWeeks,
        },
        {
          signer: user2,
          amount: baseAmount.mul(3),
          action: "deposit",
          lock: lockDay,
        },
        {
          signer: user3,
          amount: baseAmount.mul(2),
          action: "deposit",
          lock: lockWeek,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.25,
      actions: [
        {
          signer: user3,
          amount: baseAmount.mul(2),
          action: "deposit",
          lock: lockTwoWeeks,
        },
        {
          signer: user2,
          amount: 0,
          action: "unbond",
        },
        {
          signer: user4,
          amount: baseAmount.mul(4),
          action: "deposit",
          lock: lockWeek,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.5,
      actions: [
        {
          signer: user2,
          amount: 0,
          action: "withdraw",
        },
        {
          signer: user4,
          amount: 0,
          action: "unbond",
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.75,
      actions: [
        {
          signer: user2,
          amount: baseAmount.mul(3),
          action: "deposit",
          lock: lockDay,
        },
        {
          signer: user4,
          amount: 0,
          action: "cancelUnbonding",
        },
        {
          signer: user3,
          amount: 0,
          action: "unbond",
        },
      ],
    },
  ];

  const rewards: RewardInfo[] = [
    {
      signer: user1,
      expectedReward: totalRewardsBase.mul(1631),
    },
    {
      signer: user2,
      expectedReward: totalRewardsBase.mul(2003),
    },
    {
      signer: user3,
      expectedReward: totalRewardsBase.mul(3841),
    },
    {
      signer: user4,
      expectedReward: totalRewardsBase.mul(2525),
    },
  ];

  return { actions, rewards };
};

export const setupAdvancedScenario5 = (ctx: TestContext): ScenarioInfo => {
  // Advanced Scenario 5:
  // (Midstream unbonding and unstaking, re-staking, unbonding canceled, reward rate change)
  //
  // Staker 1 Deposits N at 0 with two week lock (v = 2N)
  // Staker 2 Deposits 3N at 0 with one day lock (v = 3.3N)
  // Staker 3 Deposits 2N at 0 with one week lock (v = 2.8N)
  // Staker 1 Claims at 0.25
  // Staker 2 Unbonds 3N at 0.25 (v = 3N)
  // Staker 4 Deposits 4N at 0.25 with one week lock (v = 5.6N)
  // Staker 3 Deposits 2N at 0.25 with two week lock (v = 4N)
  //
  // Reward rate changed at 0.5 (1.5x rewards put in, so rate should double)
  //
  // Staker 2 Unstakes 3N at 0.5 (v = 0)
  // Staker 4 Unbonds 4N at 0.5 (v = 4N)
  // Staker 1 Claims at 0.5
  // Staker 1 Unbonds at 0.5 (v = N)
  // Staker 4 cancels unbonding at 0.75 (v = 5.6N)
  // Staker 3 Unbonds 4N at 0.75 (v = 4N)
  // Staker 4 Unbonds at 1 (v = 4N)
  // Staker 3 Unstakes at 1 (v = 0)
  // Staker 2 Stakes 3N at 1 with one-day lock (v = 3.3N)
  // Staker 3 Deposits N at 1.25 with two week lock (v = 2N)
  // Staker 2 Unbonds at 1.25 (v = 3N)
  // Staker 1 Unstakes at 1.25 (v = 0)
  //
  //
  //            Staker 1 %        Staker 2 %      Staker 3 %     Staker 4 %
  // At T = 0:     24.69            40.74           34.57               0
  // At T = 0.25:  11.49            17.24           39.08           32.18
  // At T = 0.5:    8.47                0           57.63           33.90     (x2 weight)
  // At T = 0.75:   9.43                0           37.73           52.83     (x2 weight)
  // At T = 1:     12.05            39.76               0           48.19     (x2 weight)
  // At T = 1.25:      0            33.33           22.22           44.44     (x2 weight)
  // Totals:        9.61            20.42           30.88           39.09

  const {
    signers: [admin, user1, user2, user3, user4],
  } = ctx;

  const baseAmount = ether("100");
  const totalTime = oneMonthSec;
  const totalRewardsBase = TOTAL_REWARDS.div(10).mul(25).div(10000);

  const actions: Action[] = [
    {
      timestamp: programStart + 5,
      actions: [
        {
          signer: user1,
          amount: baseAmount,
          action: "deposit",
          lock: lockTwoWeeks,
        },
        {
          signer: user2,
          amount: baseAmount.mul(3),
          action: "deposit",
          lock: lockDay,
        },
        {
          signer: user3,
          amount: baseAmount.mul(2),
          action: "deposit",
          lock: lockWeek,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.25,
      actions: [
        {
          signer: user1,
          amount: 0,
          action: "claim",
        },
        {
          signer: user3,
          amount: baseAmount.mul(2),
          action: "deposit",
          lock: lockTwoWeeks,
        },
        {
          signer: user2,
          amount: 0,
          action: "unbond",
        },
        {
          signer: user4,
          amount: baseAmount.mul(4),
          action: "deposit",
          lock: lockWeek,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.5,
      actions: [
        {
          signer: admin,
          amount: TOTAL_REWARDS.div(10).mul(15),
          action: "notify",
        },
        {
          signer: user2,
          amount: 0,
          action: "withdraw",
        },
        {
          signer: user4,
          amount: 0,
          action: "unbond",
        },
        {
          signer: user1,
          amount: 0,
          action: "claim",
        },
        {
          signer: user1,
          amount: 0,
          action: "unbond",
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 0.75,
      actions: [
        {
          signer: user4,
          amount: 0,
          action: "cancelUnbonding",
        },
        {
          signer: user3,
          amount: 0,
          action: "unbond",
        },
      ],
    },
    {
      timestamp: programStart + totalTime,
      actions: [
        {
          signer: user4,
          amount: 0,
          action: "unbond",
        },
        {
          signer: user3,
          amount: 0,
          action: "withdraw",
        },
        {
          signer: user2,
          amount: baseAmount.mul(3),
          action: "deposit",
          lock: lockDay,
        },
      ],
    },
    {
      timestamp: programStart + totalTime * 1.25,
      actions: [
        {
          signer: user2,
          amount: 0,
          action: "unbond",
        },
        {
          signer: user1,
          amount: 0,
          action: "withdraw",
        },
        {
          signer: user3,
          amount: baseAmount,
          action: "deposit",
          lock: lockTwoWeeks,
        },
      ],
    },
  ];

  const rewards: RewardInfo[] = [
    {
      signer: user1,
      expectedReward: totalRewardsBase.mul(961),
    },
    {
      signer: user2,
      expectedReward: totalRewardsBase.mul(2042),
    },
    {
      signer: user3,
      expectedReward: totalRewardsBase.mul(3088),
    },
    {
      signer: user4,
      expectedReward: totalRewardsBase.mul(3909),
    },
  ];

  return { actions, rewards };
};

export const runScenario = async (
  ctx: TestContext,
  actions: Action[],
  logCheckpoints = false,
): Promise<{ [user: string]: BigNumberish }> => {
  const { staking, signers } = ctx;
  const claims: { [user: string]: BigNumberish } = {};

  let haveNotified = false;

  await staking.setRewardsDuration(oneMonthSec);

  const doNotify = async (rewards: BigNumberish) => {
    if (haveNotified) return;

    await setNextBlockTimestamp(programStart);
    await staking.notifyRewardAmount(rewards);
    haveNotified = true;
  };

  // Run through scenario from beginning of program until end
  for (const batch of actions) {
    const { timestamp, actions: batchActions } = batch;

    // Make deposit
    if (timestamp > programStart) {
      await doNotify(TOTAL_REWARDS);
    }

    await setNextBlockTimestamp(timestamp);

    let tx: ContractTransaction;

    for (const a of batchActions) {
      const { signer, amount, action, lock } = a;

      if (action === "deposit") {
        tx = await staking.connect(signer).stake(amount, lock!);
      } else if (action === "claim") {
        // No need to roll, just claim - keep track of amount rewarded
        tx = await staking.connect(signer).claimAll();
        const receipt = await tx.wait();

        const claimEvents = receipt.events?.filter(e => e.event === "Claim");

        let reward = ethers.BigNumber.from(0);
        for (const event of claimEvents!) {
          expect(event).to.not.be.undefined;
          expect(event?.args?.[0]).to.eq(signer.address);

          reward = reward.add(event?.args?.[2]);
        }

        if (claims[signer.address]) {
          claims[signer.address] = ethers.BigNumber.from(claims[signer.address]).add(reward);
        } else {
          claims[signer.address] = reward;
        }
      } else if (action === "unbond") {
        // No need to roll, just claim - keep track of amount rewarded
        tx = await staking.connect(signer).unbondAll();
      } else if (action === "cancelUnbonding") {
        tx = await staking.connect(signer).cancelUnbondingAll();
      } else if (action === "withdraw") {
        // No need to roll, just claim - keep track of amount rewarded
        tx = await staking.connect(signer).unstakeAll();
        const receipt = await tx.wait();

        const withdrawEvents = receipt.events?.filter(e => e.event === "Unstake");

        let reward = ethers.BigNumber.from(0);
        for (const event of withdrawEvents!) {
          expect(event).to.not.be.undefined;
          expect(event?.args?.[0]).to.eq(signer.address);

          reward = reward.add(event?.args?.[3]);
        }

        if (claims[signer.address]) {
          claims[signer.address] = ethers.BigNumber.from(claims[signer.address]).add(reward);
        } else {
          claims[signer.address] = reward;
        }
      } else if (action === "notify") {
        tx = await staking.notifyRewardAmount(amount);
      }
    }

    await tx!.wait();

    // Actions for timestamp done

    if (logCheckpoints) {
      // Report balances for all coins
      const { staking, tokenDist } = ctx;

      console.log("Timestamp:", timestamp);
      console.log("Total Staked:", await (await staking.totalDeposits()).toString());
      console.log("Total Staked With Boost:", await (await staking.totalDepositsWithBoost()).toString());
      console.log("Balances");
      for (const user of signers.slice(1, 5)) {
        console.log(`Wallet balance (${user.address}): ${await tokenDist.balanceOf(user.address)}`);
      }
      console.log();
    }
  }

  // Now roll to end - all staking should be processed
  await setNextBlockTimestamp(programEnd);

  return claims;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const shuffle = (array: any[]) => {
  let currentIndex = array.length,
    randomIndex;

  // While there remain elements to shuffle...
  while (currentIndex != 0) {
    // Pick a remaining element...
    randomIndex = Math.floor(Math.random() * currentIndex);
    currentIndex--;

    // And swap it with the current element.
    [array[currentIndex], array[randomIndex]] = [array[randomIndex], array[currentIndex]];
  }

  return array;
};
