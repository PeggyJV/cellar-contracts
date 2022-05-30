// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";

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

    // ===================== Structs ======================

    enum Lock {
        short,
        medium,
        long
    }

    struct UserStake {
        uint112 amount;
        uint112 amountWithBoost;
        uint112 rewardPerTokenPaid;
        uint112 rewards;
        uint32 unbondTimestamp;
        Lock lock;
    }

    // ============== Public State Variables ==============

    function stakingToken() external returns (ERC20);

    function distributionToken() external returns (ERC20);

    function epochDuration() external returns (uint256);

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

    function rewardPerToken() external view returns (uint256);

    function getUserStakes(address user) external view returns (UserStake[] memory);
}
