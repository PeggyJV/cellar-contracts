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

    /**
     * @notice Emitted when assets are deposited into cellar.
     * @param caller the address of the caller
     * @param token the address of token the cellar receives
     * @param owner the address of the owner of shares
     * @param assets the amount of assets being deposited
     * @param shares the amount of shares minted to owner
     */
    event Deposit(
        address indexed caller,
        address indexed owner,
        address indexed token,
        uint256 assets,
        uint256 shares
    );

    error CallerNoStrategyProvider();
    error IncorrectPercentageSum();
    error IncorrectArrayLength();
    error IncorrectPercentageValue();
    error TokenIsNotSupported();

    /**
     * @notice Attempted an action with zero shares.
     */
    error ZeroShares();
}