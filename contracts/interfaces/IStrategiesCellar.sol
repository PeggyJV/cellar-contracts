// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/// @title interface for StrategiesCellar
interface IStrategiesCellar {
    // ======================================= EVENTS =======================================

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

    /**
     * @notice Emitted when assets are withdrawn from cellar.
     * @param receiver the address of the receiver of the withdrawn assets
     * @param owner the address of the owner of the shares
     * @param token the address of the token withdrawn
     * @param assets the amount of assets being withdrawn
     * @param shares the amount of shares burned from owner
     */
    event Withdraw(
        address indexed receiver,
        address indexed owner,
        address indexed token,
        uint256 assets,
        uint256 shares
    );

    // ======================================= ERRORS =======================================

    error CallerNoStrategyProvider();
    error CallerNoCellarVault();
    error IncorrectPercentageSum();
    error IncorrectArrayLength();
    error IncorrectPercentageValue();
    error TokenIsNotSupported();
    error InputTokenNotAllowed();
    error OutputTokenNotAllowed();

    /**
     * @notice Attempted an action with zero assets.
     */
    error ZeroAssets();

    /**
     * @notice Attempted an action with zero shares.
     */
    error ZeroShares();

    // ======================================= STRUCTS =======================================

    struct Strategy {
        uint256[] subStrategiesIds; // list of lower level strategies
        uint8[] proportions; // percentage distribution of the deposits by strategies
        uint8[] maxProportions; // maximum allowed percentages for each subStrategy
        uint256[] subStrategiesShares; // sub strategies shares
        bool isBase; // true if this is a base level strategy
        address baseInactiveAsset; // address(0) if isBase == false
        address baseActiveAsset; // aToken corresponding to the baseInactiveAsset
    }

    // ================================== FUNCTIONS ==================================

    function activeBaseAssets(uint256 _baseStrategyId) external view returns (uint256);
    function activeBaseAssetsUSDC(uint256 _baseStrategyId) external view returns (uint256);
    function inactiveBaseAssets(uint256 _baseStrategyId) external view returns (uint256);
    function inactiveBaseAssetsUSDC(uint256 _baseStrategyId) external view returns (uint256);
    function totalBaseAssets(uint256 _baseStrategyId) external view returns (uint256);

    function afterEnterBaseStrategy(uint256 _baseStrategyId) external;

    function getSubStrategiesIds(uint256 strategyId) external view returns(uint256[] memory);
    function getProportions(uint256 strategyId) external view returns(uint8[] memory);
    function getMaxProportions(uint256 strategyId) external view returns(uint8[] memory);
    function getSubStrategiesShares(uint256 strategyId) external view returns(uint256[] memory);
    function getIsBase(uint256 strategyId) external view returns(bool);
    function getBaseInactiveAsset(uint256 strategyId) external view returns(address);
    function getBaseActiveAsset(uint256 strategyId) external view returns(address);
    function strategyCount() external view returns(uint256);
}
