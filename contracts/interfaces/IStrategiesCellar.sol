// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/// @title interface for StrategiesCellar
interface IStrategiesCellar {
    event AddBaseStrategy(
        uint256 indexed strategyId
    );

    event AddStrategy(
        uint256 indexed strategyId
    );

    event UpdateStrategy(
        uint256 indexed strategyId
    );

    error CallerNoStrategyProvider();
    error IncorrectPercentageSum();
    error IncorrectArrayLength();
    error IncorrectPercentageValue();
}