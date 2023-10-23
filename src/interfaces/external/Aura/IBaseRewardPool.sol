// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IBaseRewardPool {
    // Aura Pool Example: https://etherscan.deth.net/address/0x032B676d5D55e8ECbAe88ebEE0AA10fB5f72F6CB

    function getReward(address _account, bool _claimExtras) external returns (bool);
}
