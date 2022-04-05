// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.11;

interface IStakedTokenV2 {
  function stake(address to, uint256 amount) external;

  function redeem(address to, uint256 amount) external;

  function cooldown() external;

  function claimRewards(address to, uint256 amount) external;

  function balanceOf(address account) external view returns (uint256);

  function stakersCooldowns(address account) external view returns (uint256);
}
