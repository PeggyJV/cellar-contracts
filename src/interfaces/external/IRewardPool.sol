// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

// Convex IRewardPool interface
interface IRewardPool is IERC20 {
    function getReward() external returns(bool);
    function getReward(address _account, bool _claimExtras) external returns(bool);
    function withdrawAllAndUnwrap(bool claim) external;
    function withdraw(uint256 amount, bool claim) external;
    function stake(uint256 _amount) external;
    function rewardPerToken() external view returns (uint256);
}