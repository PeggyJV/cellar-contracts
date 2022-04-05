// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/// @title interface for AaveV2StablecoinCellar
interface IAaveV2StablecoinCellar {
    // ======================================= EVENTS =======================================

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

    /**
     * @notice Emitted on deposit to Aave.
     * @param token the address of the token
     * @param amount the amount of tokens to deposit
     */
    event DepositToAave(
        address indexed token,
        uint256 amount
    );

    /**
     * @notice Emitted on withdraw from Aave.
     * @param token the address of the token
     * @param amount the amount of tokens to withdraw
     */
    event WithdrawFromAave(
        address indexed token,
        uint256 amount
    );

    /**
     * @notice Emitted on rebalance of Aave strategy.
     * @param oldAsset the address of the asset for the old strategy
     * @param newAsset the address of the asset for the new strategy
     * @param assets the amount of the new assets that has been deposited to Aave after rebalance
     */
    event Rebalance(
        address indexed oldAsset,
        address indexed newAsset,
        uint256 assets
    );

    /**
     * @notice Emitted when platform fees accrued.
     * @param fees amount of fees accrued in shares
     */
    event AccruedPlatformFees(uint256 fees);

    /**
     * @notice Emitted when performance fees accrued.
     * @param fees amount of fees accrued in shares
     */
    event AccruedPerformanceFees(uint256 fees);

    /**
     * @notice Emitted when performance fees burnt as insurance.
     * @param fees amount of fees burnt in shares
     */
    event BurntPerformanceFees(uint256 fees);

    /**
     * @notice Emitted when platform fees are transferred to Cosmos.
     * @param platformFees amount of platform fees transferred
     * @param performanceFees amount of performance fees transferred
     */
    event TransferFees(uint256 platformFees, uint256 performanceFees);

    /**
     * @notice Emitted when liquidity restriction removed.
     */
    event LiquidityRestrictionRemoved();

    /**
     * @notice Emitted when tokens accidentally sent to cellar are recovered.
     * @param token the address of the token
     * @param amount amount transferred out
     */
    event Sweep(address indexed token, uint256 amount);

    /**
     * @notice Emitted when cellar is paused.
     * @param isPaused whether the contract is paused
     */
    event Pause(bool isPaused);

    /**
     * @notice Emitted when cellar is shutdown.
     */
    event Shutdown();

    // ======================================= ERRORS =======================================

    /**
     * @notice Attempted an action with zero assets.
     */
    error ZeroAssets();

    /**
     * @notice Attempted an action with zero shares.
     */
    error ZeroShares();

    /**
     * @notice Attempted deposit more liquidity over the liquidity limit.
     * @param maxLiquidity the max liquidity
     */
    error LiquidityRestricted(uint256 maxLiquidity);

    /**
     * @notice Attempted deposit more than the per wallet limit.
     * @param maxDeposit the max deposit
     */
    error DepositRestricted(uint256 maxDeposit);

    /**
     * @notice Current asset is updated to an asset not supported by Aave.
     * @param unsupportedToken address of the unsupported token
     */
    error TokenIsNotSupportedByAave(address unsupportedToken);

    /**
     * @notice Attempted to sweep an asset that is managed by the cellar.
     * @param token address of the token that can't be sweeped
     */
    error ProtectedAsset(address token);

    /**
     * @notice Attempted rebalance into the same asset.
     * @param asset address of the asset
     */
    error SameAsset(address asset);

    /**
     * @notice Attempted action was prevented due to contract being shutdown.
     */
    error ContractShutdown();

    /**
     * @notice Attempted action was prevented due to contract being paused.
     */
    error ContractPaused();

    /**
     * @notice Attempted to shutdown the contract when it was already shutdown.
     */
    error AlreadyShutdown();

    // ======================================= STRUCTS =======================================

    /**
     * @notice Stores user deposit data.
     * @param assets amount of assets deposited
     * @param shares amount of shares that were minted for their deposit
     * @param timeDeposited timestamp of when the user deposited
     */
    struct UserDeposit {
        uint112 assets;
        uint112 shares;
        uint32 timeDeposited;
    }

    // ================================= DEPOSIT/WITHDRAWAL OPERATIONS =================================

    function deposit(uint256 assets, address receiver) external returns (uint256);

    function mint(uint256 shares, address receiver) external returns (uint256);

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    // ==================================== ACCOUNTING OPERATIONS ====================================

    function activeAssets() external view returns (uint256);

    function inactiveAssets() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function previewDeposit(uint256 assets) external view returns (uint256);

    function previewMint(uint256 shares) external view returns (uint256);

    function previewWithdraw(uint256 assets) external view returns (uint256);

    function previewRedeem(uint256 shares) external view returns (uint256);

    // ======================================= STATE INFORMATION =====================================

    function depositBalances(address user) external view returns (
        uint256 userActiveShares,
        uint256 userInactiveShares,
        uint256 userActiveAssets,
        uint256 userInactiveAssets
    );

    function numDeposits(address user) external view returns (uint256);

    // ============================ DEPOSIT/WITHDRAWAL LIMIT OPERATIONS ============================

    function maxDeposit(address owner) external view returns (uint256);

    function maxMint(address owner) external view returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256);

    function maxRedeem(address owner) external view returns (uint256);

    // ======================================= FEE OPERATIONS =======================================

    function accrueFees() external;

    function transferFees() external;

    // ======================================= ADMIN OPERATIONS =======================================

    function enterStrategy() external;

    function rebalance(
        address[9] memory route,
        uint256[3][4] memory swapParams,
        uint256 minAmountOut
    ) external;

    function reinvest(uint256 minAmountOut) external;

    function claimAndUnstake() external returns (uint256 claimed);

    function sweep(address token) external;

    function removeLiquidityRestriction() external;

    function setPause(bool _isPaused) external;

    function shutdown() external;

    // ================================== SHARE TRANSFER OPERATIONS ==================================

    function transferFrom(
        address from,
        address to,
        uint256 amount,
        bool onlyActive
    ) external returns (bool);
}
