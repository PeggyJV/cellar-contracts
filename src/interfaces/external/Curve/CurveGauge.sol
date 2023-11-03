// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface CurveGauge {
    function deposit(uint256 amount, address to) external;

    function withdraw(uint256 amount, bool claimRewards) external;

    function claim_rewards(address to) external;

    function balanceOf(address user) external view returns (uint256);
}
