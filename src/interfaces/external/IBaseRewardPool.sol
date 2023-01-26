// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IBaseRewardPool {
    function getReward(address _account, bool _claimExtra) external;

    function pid() external view returns (uint256);

    function extraRewards(uint256 index) external view returns (address);

    function extraRewardsLength() external view returns (uint256);

    function balanceOf(address _account) external view returns (uint256);

    function withdrawAndUnwrap(uint256 _amount, bool _claimRewards) external;

    function earned(address _account) external view returns (uint256);
}
