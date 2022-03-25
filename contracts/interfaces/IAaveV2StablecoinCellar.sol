// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

/// @title interface for AaveV2StablecoinCellar
interface IAaveV2StablecoinCellar {
    // ======================================= EVENTS =======================================

    /**
     * @notice Emitted when assets are deposited into cellar.
     * @param caller the address of the caller
     * @param token the address of token the cellar receives (not necessarily the one deposited)
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
     * @notice Emitted when tokens swapped.
     * @param tokenIn the address of the tokenIn
     * @param amountIn the amount of the tokenIn
     * @param tokenOut the address of the tokenOut
     * @param amountOut the amount of the tokenOut
     */
    event Swapped(
        address indexed tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut
    );

    /**
     * @notice Emitted on deposit to Aave.
     * @param token the address of the token of the lending position
     * @param assets the amount that has been deposited
     */
    event DepositToAave(
        address indexed token,
        uint256 assets
    );

    /**
     * @notice Emitted on redeem from Aave.
     * @param token the address of the redeemed token
     * @param assets the amount that has been redeemed
     */
    event RedeemFromAave(
        address indexed token,
        uint256 assets
    );

    /**
     * @notice Emitted on rebalance of Aave lending position.
     * @param oldLendingToken the address of the token of the old lending position
     * @param newLendingToken the address of the token of the new lending position
     * @param assets the amount of the new lending tokens that has been deposited to Aave after rebalance
     */
    event Rebalance(
        address indexed oldLendingToken,
        address indexed newLendingToken,
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
     * @notice Emitted when tokens accidently sent to cellar are recovered.
     * @param token the address of the token
     * @param amount amount transferred out
     */
    event Sweep(address indexed token, uint256 amount);

    /**
     * @notice Emitted when an input token is approved or unapproved.
     * @param token the address of the token
     * @param isApproved whether it is approved
     */
    event SetInputToken(address token, bool isApproved);

    /**
     * @notice Emitted when cellar is paused.
     * @param caller address that set the pause
     * @param isPaused whether the contract is paused
     */
    event Pause(address caller, bool isPaused);

    /**
     * @notice Emitted when cellar is shutdown.
     * @param caller address that called the shutdown
     */
    event Shutdown(address caller);

    // ======================================= ERRORS =======================================

    /**
     * @notice Attempted an action with a token that is not approved.
     * @param unapprovedToken address of the unapproved token
     */
    error UnapprovedToken(address unapprovedToken);

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
     * @notice Current lending token is updated to an asset not supported by Aave.
     * @param unsupportedToken address of the unsupported token
     */
    error TokenIsNotSupportedByAave(address unsupportedToken);

    /**
     * @notice Attempted to sweep an asset that is managed by the cellar.
     * @param token address of the token that can't be sweeped
     */
    error ProtectedAsset(address token);

    /**
     * @notice Attempted rebalance into the same lending token.
     * @param lendingToken address of the lending token
     */
    error SameLendingToken(address lendingToken);

    /**
     * @notice Specified a swap path that doesn't make sense for the action attempted.
     * @param path the invalid swap path that was attempted
     */
    error InvalidSwapPath(address[] path);

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
        uint256 assets;
        uint256 shares;
        uint256 timeDeposited;
    }

   /**
     * @notice Stores fee data.
     * @param lastTimeAccruedPlatformFees timestamp of last time platform fees were accrued
     * @param lastActiveAssets amount of active assets in cellar last time performance fees were accrued
     * @param lastNormalizedIncome normalized income index of asset last time performance fees were accrued
     * @param accruedPlatformFees amount of platform fees that have been accrued awaiting transfer
     * @param accruedPerformanceFees amount of performance fees that have been accrued awaiting transfer
     */
    struct FeesData {
        uint256 lastTimeAccruedPlatformFees;
        uint256 lastActiveAssets;
        uint256 lastNormalizedIncome;
        // Fees are taken in shares and redeemed for assets at the time they are transferred from the
        // cellar to Cosmos to be distributed.
        uint256 accruedPlatformFees;
        uint256 accruedPerformanceFees;
    }

    // ======================================= FUNCTIONS =======================================

    function deposit(
        uint256 assets,
        address receiver,
        address[] memory path,
        uint256 minAssetsIn
    ) external returns (uint256 shares);

    function deposit(uint256 assets) external returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    function withdraw(uint256 assets) external returns (uint256 shares);

    function inactiveAssets() external view returns (uint256);

    function activeAssets() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function enterStrategy() external;

    function reinvest(address[] memory path, uint256 minAssetsOut) external;

    function claimAndUnstake() external returns (uint256 claimed);

    function rebalance(address[] memory path, uint256 minNewLendingTokenAmount) external;

    function accrueFees() external;

    function transferFees() external;

    function setInputToken(address token, bool isApproved) external;

    function removeLiquidityRestriction() external;

    function sweep(address token) external;
}
