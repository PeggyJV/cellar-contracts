// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

/// @title interface for AaveStablecoinCellar
interface IAaveStablecoinCellar {
    /**
     * @notice Emitted when assets are deposited into cellar.
     * @param caller the address of the caller
     * @param owner the address of the owner of shares
     * @param assets the amount of assets being deposited
     * @param shares the amount of shares minted to owner
     */
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when assets are withdrawn from cellar.
     * @param caller the address of the caller
     * @param owner the address of the owner of shares
     * @param assets the amount of assets being withdrawn
     * @param shares the amount of shares burned from owner
     */
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
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
     * @param token the address of the token of the new lending position
     * @param assets the amount that has been deposited
     */
    event Rebalance(
        address indexed token,
        uint256 assets
    );

    /**
     * @notice Emitted when platform fees are transferred to Cosmos.
     * @param assets amount of assets transferred
     */
    event TransferPlatformFees(uint256 assets);

    /**
     * @notice Emitted when performance fees are transferred to Cosmos.
     * @param assets amount of assets transferred
     */
    event TransferPerformanceFees(uint256 assets);

    /**
     * @notice Emitted when platform fees are changed.
     * @param oldFee what fees were set to before
     * @param newFee what fees were set to after
     */
    event ChangedPlatformFees(uint256 oldFee, uint256 newFee);

    /**
     * @notice Emitted when performance fees are changed.
     * @param oldFee what fees were set to before
     * @param newFee what fees were set to after
     */
    event ChangedPerformanceFees(uint256 oldFee, uint256 newFee);

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

    error NonSupportedToken();
    error PathIsTooShort();
    error ZeroAmount();
    error GreaterThanMaxValue();
    error LiquidityRestricted();

    error TokenIsNotSupportedByAave();
    error NotEnoughTokenLiquidity();
    error InsufficientAaveDepositBalance();

    error NoNonemptyUserDeposits();

    error ProtectedAsset();

    error SameLendingToken();

    function deposit(address token, uint256 assets, uint256 minAssetsIn, address receiver) external returns (uint256 shares);

    function deposit(uint256 assets) external returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256);

    function depositAndEnter(
        address token,
        uint256 assets,
        uint256 minAssetsIn,
        address receiver
    ) external returns (uint256 shares);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    function withdraw(uint256 assets) external returns (uint256 shares);

    function inactiveAssets() external view returns (uint256);

    function activeAssets() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external returns (uint256 amountOut);

    function multihopSwap(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external returns (uint256);

    function sushiswap(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external returns (uint256);

    function enterStrategy() external;

    function reinvest(uint256 amount, uint256 minAssetsOut) external;

    function reinvest(uint256 minAssetsOut) external;

    function claimAndUnstake(uint256 amount) external returns (uint256 claimed);

    function claimAndUnstake() external returns (uint256);

    function redeemFromAave(address token, uint256 amount) external returns (uint256 withdrawnAmount);

    function rebalance(address newLendingToken, uint256 minNewLendingTokenAmount) external;

    function setPlatformFee(uint256 newFee) external;

    function setPerformanceFee(uint256 newFee) external;

    function accruePlatformFees() external;

    function transferPlatformFees() external;

    function transferPerformanceFees() external;

    function setInputToken(address token, bool isApproved) external;

    function removeLiquidityRestriction() external;

    function sweep(address token) external;
}
