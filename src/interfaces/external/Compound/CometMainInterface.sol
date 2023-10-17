// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./CometCore.sol";

/**
 * @title Compound's Comet Main Interface (without Ext)
 * @notice An efficient monolithic money market protocol
 * @author Compound
 */
abstract contract CometMainInterface is CometCore {
    error Absurd();
    error AlreadyInitialized();
    error BadAsset();
    error BadDecimals();
    error BadDiscount();
    error BadMinimum();
    error BadPrice();
    error BorrowTooSmall();
    error BorrowCFTooLarge();
    error InsufficientReserves();
    error LiquidateCFTooLarge();
    error NoSelfTransfer();
    error NotCollateralized();
    error NotForSale();
    error NotLiquidatable();
    error Paused();
    error SupplyCapExceeded();
    error TimestampTooLarge();
    error TooManyAssets();
    error TooMuchSlippage();
    error TransferInFailed();
    error TransferOutFailed();
    error Unauthorized();

    event Supply(address indexed from, address indexed dst, uint amount);
    event Transfer(address indexed from, address indexed to, uint amount);
    event Withdraw(address indexed src, address indexed to, uint amount);

    event SupplyCollateral(address indexed from, address indexed dst, address indexed asset, uint amount);
    event TransferCollateral(address indexed from, address indexed to, address indexed asset, uint amount);
    event WithdrawCollateral(address indexed src, address indexed to, address indexed asset, uint amount);

    /// @notice Event emitted when a borrow position is absorbed by the protocol
    event AbsorbDebt(address indexed absorber, address indexed borrower, uint basePaidOut, uint usdValue);

    /// @notice Event emitted when a user's collateral is absorbed by the protocol
    event AbsorbCollateral(
        address indexed absorber,
        address indexed borrower,
        address indexed asset,
        uint collateralAbsorbed,
        uint usdValue
    );

    /// @notice Event emitted when a collateral asset is purchased from the protocol
    event BuyCollateral(address indexed buyer, address indexed asset, uint baseAmount, uint collateralAmount);

    /// @notice Event emitted when an action is paused/unpaused
    event PauseAction(bool supplyPaused, bool transferPaused, bool withdrawPaused, bool absorbPaused, bool buyPaused);

    /// @notice Event emitted when reserves are withdrawn by the governor
    event WithdrawReserves(address indexed to, uint amount);

    function supply(address asset, uint amount) external virtual;

    function supplyTo(address dst, address asset, uint amount) external virtual;

    function supplyFrom(address from, address dst, address asset, uint amount) external virtual;

    function transfer(address dst, uint amount) external virtual returns (bool);

    function transferFrom(address src, address dst, uint amount) external virtual returns (bool);

    function transferAsset(address dst, address asset, uint amount) external virtual;

    function transferAssetFrom(address src, address dst, address asset, uint amount) external virtual;

    function withdraw(address asset, uint amount) external virtual;

    function withdrawTo(address to, address asset, uint amount) external virtual;

    function withdrawFrom(address src, address to, address asset, uint amount) external virtual;

    function approveThis(address manager, address asset, uint amount) external virtual;

    function withdrawReserves(address to, uint amount) external virtual;

    function absorb(address absorber, address[] calldata accounts) external virtual;

    function buyCollateral(address asset, uint minAmount, uint baseAmount, address recipient) external virtual;

    function quoteCollateral(address asset, uint baseAmount) public view virtual returns (uint);

    function getAssetInfo(uint8 i) public view virtual returns (AssetInfo memory);

    function getAssetInfoByAddress(address asset) public view virtual returns (AssetInfo memory);

    function getCollateralReserves(address asset) public view virtual returns (uint);

    function getReserves() public view virtual returns (int);

    function getPrice(address priceFeed) public view virtual returns (uint);

    function isBorrowCollateralized(address account) public view virtual returns (bool);

    function isLiquidatable(address account) public view virtual returns (bool);

    function totalSupply() external view virtual returns (uint256);

    function totalBorrow() external view virtual returns (uint256);

    function balanceOf(address owner) public view virtual returns (uint256);

    function borrowBalanceOf(address account) public view virtual returns (uint256);

    function pause(
        bool supplyPaused,
        bool transferPaused,
        bool withdrawPaused,
        bool absorbPaused,
        bool buyPaused
    ) external virtual;

    function isSupplyPaused() public view virtual returns (bool);

    function isTransferPaused() public view virtual returns (bool);

    function isWithdrawPaused() public view virtual returns (bool);

    function isAbsorbPaused() public view virtual returns (bool);

    function isBuyPaused() public view virtual returns (bool);

    function accrueAccount(address account) external virtual;

    function getSupplyRate(uint utilization) public view virtual returns (uint64);

    function getBorrowRate(uint utilization) public view virtual returns (uint64);

    function getUtilization() public view virtual returns (uint);

    function governor() external view virtual returns (address);

    function pauseGuardian() external view virtual returns (address);

    function baseToken() external view virtual returns (address);

    function baseTokenPriceFeed() external view virtual returns (address);

    function extensionDelegate() external view virtual returns (address);

    /// @dev uint64
    function supplyKink() external view virtual returns (uint);

    /// @dev uint64
    function supplyPerSecondInterestRateSlopeLow() external view virtual returns (uint);

    /// @dev uint64
    function supplyPerSecondInterestRateSlopeHigh() external view virtual returns (uint);

    /// @dev uint64
    function supplyPerSecondInterestRateBase() external view virtual returns (uint);

    /// @dev uint64
    function borrowKink() external view virtual returns (uint);

    /// @dev uint64
    function borrowPerSecondInterestRateSlopeLow() external view virtual returns (uint);

    /// @dev uint64
    function borrowPerSecondInterestRateSlopeHigh() external view virtual returns (uint);

    /// @dev uint64
    function borrowPerSecondInterestRateBase() external view virtual returns (uint);

    /// @dev uint64
    function storeFrontPriceFactor() external view virtual returns (uint);

    /// @dev uint64
    function baseScale() external view virtual returns (uint);

    /// @dev uint64
    function trackingIndexScale() external view virtual returns (uint);

    /// @dev uint64
    function baseTrackingSupplySpeed() external view virtual returns (uint);

    /// @dev uint64
    function baseTrackingBorrowSpeed() external view virtual returns (uint);

    /// @dev uint104
    function baseMinForRewards() external view virtual returns (uint);

    /// @dev uint104
    function baseBorrowMin() external view virtual returns (uint);

    /// @dev uint104
    function targetReserves() external view virtual returns (uint);

    function numAssets() external view virtual returns (uint8);

    function decimals() external view virtual returns (uint8);

    function initializeStorage() external virtual;

    // extra functions to access public vars as needed for Sommelier integration

    /// @notice Mapping of users to collateral data per collateral asset
    /// @dev See CometStorage.sol for struct UserCollateral
    function userCollateral(address, address) external returns (UserCollateral);

    /// @notice Mapping of users to base principal and other basic data
    /// @dev See CometStorage.sol for struct UserBasic
    function userBasic(address) external returns (UserBasic);
}
