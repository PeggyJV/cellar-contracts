// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

/**
 * @title IBaseRewardPool
 * @author crispymangoes, 0xeincodes
 * @notice Interface with specific functions to interact with Convex BaseRewardsPool contracts
 */
interface IBaseRewardPool {
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
}
