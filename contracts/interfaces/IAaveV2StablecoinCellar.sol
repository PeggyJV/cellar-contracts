// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

/// @title interface for AaveV2StablecoinCellar
interface IAaveV2StablecoinCellar {
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
     * @param feeInShares amount of fees transferred (in shares)
     * @param feeInAssets amount of fees transferred (in assets)
     */
    event TransferFees(uint256 feeInShares, uint256 feeInAssets);

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
     * @param currentLiquidity the current liquidity
     * @param maxLiquidity the max liquidity
     */
    error LiquidityRestricted(uint256 currentLiquidity, uint256 maxLiquidity);

    /**
     * @notice Attempted deposit more than the per wallet limit.
     * @param currentDeposit the current deposit
     * @param maxDeposit the max deposit
     */
    error DepositRestricted(uint256 currentDeposit, uint256 maxDeposit);

    /**
     * @notice Current lending token is updated to an asset not supported by Aave.
     * @param unsupportedToken address of the unsupported token
     */
    error TokenIsNotSupportedByAave(address unsupportedToken);

    /**
     * @notice Attempted to sweep an asset that is managed by the cellar.
     * @param protectedToken address of the unsupported token
     */
    error ProtectedToken(address protectedToken);

    /**
     * @notice Attempted rebalance into the same lending token.
     * @param lendingToken address of the lending token
     */
    error SameLendingToken(address lendingToken);

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

    function deposit(
        address token,
        uint256 assets,
        uint256 minAssetsIn,
        address receiver
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

    function rebalance(address newLendingToken, uint256 minNewLendingTokenAmount) external;

    function accruePlatformFees() external;

    function transferFees() external;

    function setInputToken(address token, bool isApproved) external;

    function removeLiquidityRestriction() external;

    function sweep(address token) external;
}
