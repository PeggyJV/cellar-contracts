// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

/// @title interface for AaveV2StablecoinCellar
interface IAaveV2StablecoinCellar {
    /**
     * @notice Stores fee-related data.
     */
    struct Fees {
        /**
         * @notice Amount of yield earned since last time performance fees were accrued.
         */
        uint112 yield;
        /**
         * @notice Amount of active assets in cellar since yield was last calculated.
         */
        uint112 lastActiveAssets;
        /**
         * @notice Timestamp of last time platform fees were accrued.
         */
        uint32 lastTimeAccruedPlatformFees;
        /**
         * @notice Amount of platform fees that have been accrued awaiting transfer.
         * @dev Fees are taken in shares and redeemed for assets at the time they are transferred from
         *      the cellar to Cosmos to be distributed.
         */
        uint112 accruedPlatformFees;
        /**
         * @notice Amount of performance fees that have been accrued awaiting transfer.
         * @dev Fees are taken in shares and redeemed for assets at the time they are transferred from
         *      the cellar to Cosmos to be distributed.
         */
        uint112 accruedPerformanceFees;
    }

    // ======================================= EVENTS =======================================

    /**
     * @notice Emitted when assets are deposited into cellar.
     * @param caller the address of the caller
     * @param token the address of token the cellar receives
     * @param owner the address of the owner of shares
     * @param assets the amount of assets being deposited
     * @param shares the amount of shares minted to owner
     */
    event Deposit(address indexed caller, address indexed owner, address indexed token, uint256 assets, uint256 shares);

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
    event DepositToAave(address indexed token, uint256 amount);

    /**
     * @notice Emitted on withdraw from Aave.
     * @param token the address of the token
     * @param amount the amount of tokens to withdraw
     */
    event WithdrawFromAave(address indexed token, uint256 amount);

    /**
     * @notice Emitted upon entering cellar's inactive assets into the current position on Aave.
     * @param token the address of the asset being entered into the current position
     * @param assets amount of assets being entered
     */
    event EnterPosition(address indexed token, uint256 assets);

    /**
     * @notice Emitted upon claiming rewards and beginning cooldown period to unstake them.
     * @param rewardsClaimed amount of rewards that were claimed
     */
    event ClaimAndUnstake(uint256 rewardsClaimed);

    /**
     * @notice Emitted upon reinvesting rewards into the current position.
     * @param token the address of the asset rewards were swapped to
     * @param rewards amount of rewards swapped to be reinvested
     * @param assets amount of assets received from swapping rewards
     */
    event Reinvest(address indexed token, uint256 rewards, uint256 assets);

    /**
     * @notice Emitted on rebalance of Aave poisition.
     * @param oldAsset the address of the asset for the old position
     * @param newAsset the address of the asset for the new position
     * @param assets the amount of the new assets cellar has after rebalancing
     */
    event Rebalance(address indexed oldAsset, address indexed newAsset, uint256 assets);

    /**
     * @notice Emitted when platform fees accrued.
     * @param feesInShares amount of fees accrued in shares
     */
    event AccruedPlatformFees(uint256 feesInShares);

    /**
     * @notice Emitted when performance fees accrued.
     * @param feesInShares amount of fees accrued in shares
     */
    event AccruedPerformanceFees(uint256 feesInShares);

    /**
     * @notice Emitted when platform fees are transferred to Cosmos.
     * @param platformFees amount of platform fees transferred
     * @param performanceFees amount of performance fees transferred
     */
    event TransferFees(uint112 platformFees, uint112 performanceFees);

    /**
     * @notice Emitted when the liquidity limit is changed.
     * @param oldLimit amount the limit was changed from
     * @param newLimit amount the limit was changed to
     */
    event LiquidityLimitChanged(uint256 oldLimit, uint256 newLimit);

    /**
     * @notice Emitted when the deposit limit is changed.
     * @param oldLimit amount the limit was changed from
     * @param newLimit amount the limit was changed to
     */
    event DepositLimitChanged(uint256 oldLimit, uint256 newLimit);

    /**
     * @notice Emitted when tokens accidentally sent to cellar are recovered.
     * @param token the address of the token
     * @param amount amount transferred out
     */
    event Sweep(address indexed token, uint256 amount);

    /**
     * @notice Emitted when cellar is shutdown.
     * @param isShutdown whether the contract is shutdown
     * @param exitPosition whether to exit the current position
     */
    event Shutdown(bool isShutdown, bool exitPosition);

    // ======================================= ERRORS =======================================

    /**
     * @notice Attempted an action with zero assets.
     */
    error USR_ZeroAssets();

    /**
     * @notice Attempted an action with zero shares.
     */
    error USR_ZeroShares();

    /**
     * @notice Attempted deposit more than the per wallet limit.
     * @param maxDeposit the max deposit
     */
    error USR_DepositRestricted(uint256 maxDeposit);

    /**
     * @notice Attempted to call a function that is restricted to Gravity.
     */
    error USR_NotGravityBridge();

    /**
     * @notice Attempted deposit more liquidity over the liquidity limit.
     * @param maxLiquidity the max liquidity
     */
    error STATE_LiquidityRestricted(uint256 maxLiquidity);

    /**
     * @notice Attempted to sweep an asset that is managed by the cellar.
     * @param token address of the token that can't be sweeped
     */
    error STATE_ProtectedAsset(address token);

    /**
     * @notice Current asset is updated to an asset not supported by Aave.
     * @param unsupportedToken address of the unsupported token
     */
    error STATE_TokenIsNotSupportedByAave(address unsupportedToken);

    /**
     * @notice Attempted rebalance into the same asset.
     * @param asset address of the asset
     */
    error STATE_SameAsset(address asset);

    /**
     * @notice Attempted rebalance into an untrusted position.
     * @param asset address of the asset
     */
    error STATE_UntrustedPosition(address asset);

    /**
     * @notice Attempted action was prevented due to contract being shutdown.
     */
    error STATE_ContractShutdown();

    /**
     * @notice Attempted to shutdown the contract when it was already shutdown.
     */
    error STATE_AlreadyShutdown();

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

    function getUserBalances(address user)
        external
        view
        returns (
            uint256 userActiveShares,
            uint256 userInactiveShares,
            uint256 userActiveAssets,
            uint256 userInactiveAssets
        );

    function getUserDeposits(address user) external view returns (UserDeposit[] memory);

    // ============================ DEPOSIT/WITHDRAWAL LIMIT OPERATIONS ============================

    function maxDeposit(address owner) external view returns (uint256);

    function maxMint(address owner) external view returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256);

    function maxRedeem(address owner) external view returns (uint256);

    // ======================================= FEE OPERATIONS =======================================

    function accrueFees() external;

    function transferFees() external;

    // ======================================= ADMIN OPERATIONS =======================================

    function enterPosition() external;

    function rebalance(
        address[9] memory route,
        uint256[3][4] memory swapParams,
        uint256 minAmountOut
    ) external;

    function reinvest(uint256 minAmountOut) external;

    function claimAndUnstake() external returns (uint256 claimed);

    function sweep(address token) external;

    function setLiquidityLimit(uint256 limit) external;

    function setDepositLimit(uint256 limit) external;

    function setShutdown(bool shutdown, bool exitPosition) external;

    // ================================== SHARE TRANSFER OPERATIONS ==================================

    function transferFrom(
        address from,
        address to,
        uint256 amount,
        bool onlyActive
    ) external returns (bool);
}
