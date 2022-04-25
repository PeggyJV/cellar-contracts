// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

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
     * @param position the address of the position
     * @param assets the amount of assets to deposit
     */
    event DepositToAave(address indexed position, uint256 assets);

    /**
     * @notice Emitted on withdraw from Aave.
     * @param position the address of the position
     * @param assets the amount of assets to withdraw
     */
    event WithdrawFromAave(address indexed position, uint256 assets);

    /**
     * @notice Emitted upon entering cellar's inactive assets into the current position on Aave.
     * @param position the address of the asset being entered into the current position
     * @param assets amount of assets being entered
     */
    event EnterPosition(address indexed position, uint256 assets);

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
     * @notice Emitted when fees distributor is changed.
     * @param oldFeesDistributor address of fee distributor was changed from
     * @param newFeesDistributor address of fee distributor was changed to
     */
    event FeesDistributorChanged(bytes32 oldFeesDistributor, bytes32 newFeesDistributor);

    /**
     * @notice Emitted when tokens accidentally sent to cellar are recovered.
     * @param token the address of the token
     * @param to the address sweeped tokens were transferred to
     * @param amount amount transferred out
     */
    event Sweep(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Emitted when cellar is shutdown.
     * @param isShutdown whether the contract is shutdown
     * @param exitPosition whether to exit the current position
     */
    event Shutdown(bool isShutdown, bool exitPosition);

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

    function sweep(address token, address to) external;

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
