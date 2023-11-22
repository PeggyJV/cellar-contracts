// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title IBaseRewardPool
 * @author crispymangoes, 0xeincodes
 * @notice Interface with specific functions to interact with Convex BaseRewardsPool contracts
 */
interface IBaseRewardPool {
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);

    function stakingToken() external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function getReward(address _account, bool _claimExtras) external returns (bool);

    function rewardToken() external view returns (address);
}
