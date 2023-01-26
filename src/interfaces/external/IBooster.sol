// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IBooster {
    function deposit(
        uint256 _poolId,
        uint256 _amount,
        bool _stake
    ) external;

    function withdraw(uint256 _poolId, uint256 _amount) external;
}
