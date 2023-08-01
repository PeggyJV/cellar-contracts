// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

/**
 * @title Sommelier Staking Interface
 * @author Kevin Kennis
 *
 * @notice Full documentation in implementation contract.
 */
interface ICellarStaking {
    // ===================== Events =======================

    event Funding(uint256 rewardAmount, uint256 rewardEnd);
    event Stake(address indexed user, uint256 depositId, uint256 amount);
    event Unbond(address indexed user, uint256 depositId, uint256 amount);
    event CancelUnbond(address indexed user, uint256 depositId);
    event Unstake(address indexed user, uint256 depositId, uint256 amount, uint256 reward);
    event Claim(address indexed user, uint256 depositId, uint256 amount);
    event EmergencyStop(address owner, bool claimable);
    event EmergencyUnstake(address indexed user, uint256 depositId, uint256 amount);
    event EmergencyClaim(address indexed user, uint256 amount);
    event EpochDurationChange(uint256 duration);

    // ===================== Errors =======================

    /**
     * @notice Attempted to shutdown the contract when it was already shutdown.
     */
    error CellarStaking__AlreadyShutdown();

    /**
     * @notice The caller attempted to start a reward period, but the contract did not have enough tokens
     *         for the specified amount of rewards.
     *
     * @param rewardBalance         The amount of distributionToken held by the contract.
     * @param reward                The amount of rewards the caller attempted to distribute.
     */
    error CellarStaking__RewardsNotFunded(uint256 rewardBalance, uint256 reward);

    /**
     * @notice The caller attempted to change the next epoch duration, but there are rewards ready.
     */
    error CellarStaking__RewardsReady();

    /**
     * @notice The caller attempted to deposit stake, but there are no remaining rewards to pay out.
     */
    error CellarStaking__NoRewardsLeft();

    /**
     * @notice The caller attempted to perform an an emergency unstake, but the contract
     *         is not in emergency mode.
     */
    error CellarStaking__NoEmergencyUnstake();

    /**
     * @notice The caller attempted to perform an an emergency unstake, but the contract
     *         is not in emergency mode, or the emergency mode does not allow claiming rewards.
     */
    error CellarStaking__NoEmergencyClaim();

    /**
     * @notice The caller attempted to perform a state-mutating action (e.g. staking or unstaking)
     *         while the contract was paused.
     */
    error CellarStaking__ContractPaused();

    /**
     * @notice The caller attempted to perform a state-mutating action (e.g. staking or unstaking)
     *         while the contract was killed (placed in emergency mode).
     * @dev    Emergency mode is irreversible.
     */
    error CellarStaking__ContractKilled();

    /**
     * @notice The caller attempted to stake with a lock value that did not
     *         correspond to a valid staking time.
     *
     * @param lock                  The provided lock value.
     */
    error CellarStaking__InvalidLockValue(uint256 lock);

    /**
     * @notice The reward distributor attempted to update rewards but 0 rewards per epoch.
     *         This can also happen if there is less than 1 wei of rewards per second of the
     *         epoch - due to integer division this will also lead to 0 rewards.
     */
    error CellarStaking__ZeroRewardsPerEpoch();

    /**
     * @notice The contract owner attempted to update rewards but the new reward rate would cause overflow.
     */
    error CellarStaking__RewardTooLarge();

    /**
     * @notice User attempted to stake an amount smaller than the minimum deposit.
     *
     * @param amount                Amount user attmpted to stake.
     * @param minimumDeposit        The minimum deopsit amount accepted.
     */
    error CellarStaking__MinimumDeposit(uint256 amount, uint256 minimumDeposit);

    /**
     * @notice The specified deposit ID does not exist for the caller.
     *
     * @param depositId             The deposit ID provided for lookup.
     */
    error CellarStaking__NoDeposit(uint256 depositId);

    /**
     * @notice The user is attempting to cancel unbonding for a deposit which is not unbonding.
     *
     * @param depositId             The deposit ID the user attempted to cancel.
     */
    error CellarStaking__NotUnbonding(uint256 depositId);

    /**
     * @notice The user is attempting to unbond a deposit which has already been unbonded.
     *
     * @param depositId             The deposit ID the user attempted to unbond.
     */
    error CellarStaking__AlreadyUnbonding(uint256 depositId);

    /**
     * @notice The user is attempting to unstake a deposit which is still timelocked.
     *
     * @param depositId             The deposit ID the user attempted to unstake.
     */
    error CellarStaking__StakeLocked(uint256 depositId);

    /**
     * @notice User attempted to stake zero amount.
     */
    error CellarStaking__ZeroDeposit();

    // ===================== Structs ======================

    enum Lock {
        short,
        medium,
        long
    }

    struct UserStake {
        uint112 amount;
        uint112 amountWithBoost;
        uint32 unbondTimestamp;
        uint112 rewardPerTokenPaid;
        uint112 rewards;
        Lock lock;
    }

    // ============== Public State Variables ==============

    function stakingToken() external returns (ERC20);

    function distributionToken() external returns (ERC20);

    function currentEpochDuration() external returns (uint256);

    function nextEpochDuration() external returns (uint256);

    function rewardsReady() external returns (uint256);

    function minimumDeposit() external returns (uint256);

    function endTimestamp() external returns (uint256);

    function totalDeposits() external returns (uint256);

    function totalDepositsWithBoost() external returns (uint256);

    function rewardRate() external returns (uint256);

    function rewardPerTokenStored() external returns (uint256);

    function paused() external returns (bool);

    function ended() external returns (bool);

    function claimable() external returns (bool);

    // ================ User Functions ================

    function stake(uint256 amount, Lock lock) external;

    function unbond(uint256 depositId) external;

    function unbondAll() external;

    function cancelUnbonding(uint256 depositId) external;

    function cancelUnbondingAll() external;

    function unstake(uint256 depositId) external returns (uint256 reward);

    function unstakeAll() external returns (uint256[] memory rewards);

    function claim(uint256 depositId) external returns (uint256 reward);

    function claimAll() external returns (uint256[] memory rewards);

    function emergencyUnstake() external;

    function emergencyClaim() external;

    // ================ Admin Functions ================

    function notifyRewardAmount(uint256 reward) external;

    function setRewardsDuration(uint256 _epochDuration) external;

    function setMinimumDeposit(uint256 _minimum) external;

    function setPaused(bool _paused) external;

    function emergencyStop(bool makeRewardsClaimable) external;

    // ================ View Functions ================

    function latestRewardsTimestamp() external view returns (uint256);

    function rewardPerToken() external view returns (uint256, uint256);

    function getUserStakes(address user) external view returns (UserStake[] memory);
}
