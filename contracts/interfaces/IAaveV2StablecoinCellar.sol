// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { IAaveIncentivesController } from "../interfaces/IAaveIncentivesController.sol";
import { IStakedTokenV2 } from "../interfaces/IStakedTokenV2.sol";
import { ICurveSwaps } from "../interfaces/ICurveSwaps.sol";
import { ISushiSwapRouter } from "../interfaces/ISushiSwapRouter.sol";
import { ILendingPool } from "../interfaces/ILendingPool.sol";
import { IGravity } from "../interfaces/IGravity.sol";

/**
 * @title Interface for AaveV2StablecoinCellar
 */
interface IAaveV2StablecoinCellar {
    // ======================================== POSITION STORAGE ========================================

    function assetAToken() external view returns (ERC20);

    function assetDecimals() external view returns (uint8);

    function totalBalance() external view returns (uint240);

    // ========================================= ACCRUAL CONFIG =========================================

    /**
     * @notice Emitted when accrual period is changed.
     * @param oldPeriod time the period was changed from
     * @param newPeriod time the period was changed to
     */
    event AccrualPeriodChanged(uint32 oldPeriod, uint32 newPeriod);

    function accrualPeriod() external view returns (uint32);

    function lastAccrual() external view returns (uint64);

    function maxLocked() external view returns (uint160);

    function setAccrualPeriod(uint32 newAccrualPeriod) external;

    // =========================================== FEES CONFIG ===========================================

    /**
     * @notice Emitted when platform fees is changed.
     * @param oldPlatformFee value platform fee was changed from
     * @param newPlatformFee value platform fee was changed to
     */
    event PlatformFeeChanged(uint64 oldPlatformFee, uint64 newPlatformFee);

    /**
     * @notice Emitted when performance fees is changed.
     * @param oldPerformanceFee value performance fee was changed from
     * @param newPerformanceFee value performance fee was changed to
     */
    event PerformanceFeeChanged(uint64 oldPerformanceFee, uint64 newPerformanceFee);

    /**
     * @notice Emitted when fees distributor is changed.
     * @param oldFeesDistributor address of fee distributor was changed from
     * @param newFeesDistributor address of fee distributor was changed to
     */
    event FeesDistributorChanged(bytes32 oldFeesDistributor, bytes32 newFeesDistributor);

    function platformFee() external view returns (uint64);

    function performanceFee() external view returns (uint64);

    function feesDistributor() external view returns (bytes32);

    function setFeesDistributor(bytes32 newFeesDistributor) external;

    // ======================================== TRUST CONFIG ========================================

    /**
     * @notice Emitted when trust for a position is changed.
     * @param position address of the position that trust was changed for
     * @param trusted whether the position was trusted or untrusted
     */
    event TrustChanged(address position, bool trusted);

    function isTrusted(ERC20) external view returns (bool);

    function setTrust(ERC20 position, bool trust) external;

    // ======================================== LIMITS CONFIG ========================================

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

    function liquidityLimit() external view returns (uint256);

    function depositLimit() external view returns (uint256);

    function setLiquidityLimit(uint256 newLimit) external;

    function setDepositLimit(uint256 newLimit) external;

    // ======================================== EMERGENCY LOGIC ========================================

    /**
     * @notice Emitted when cellar is shutdown.
     * @param emptyPositions whether the current position(s) was exited
     */
    event ShutdownInitiated(bool emptyPositions);

    /**
     * @notice Emitted when shutdown is lifted.
     */
    event ShutdownLifted();

    function isShutdown() external view returns (bool);

    function initiateShutdown(bool emptyPosition) external;

    function liftShutdown() external;

    // ========================================== IMMUTABLES ==========================================

    function curveRegistryExchange() external view returns (ICurveSwaps);

    function sushiswapRouter() external view returns (ISushiSwapRouter);

    function lendingPool() external view returns (ILendingPool);

    function incentivesController() external view returns (IAaveIncentivesController);

    function gravityBridge() external view returns (IGravity);

    function stkAAVE() external view returns (IStakedTokenV2);

    function AAVE() external view returns (ERC20);

    function WETH() external view returns (ERC20);

    // ======================================= ACCOUNTING LOGIC =======================================

    function totalHoldings() external view returns (uint256);

    function totalLocked() external view returns (uint256);

    // ======================================== ACCRUAL LOGIC ========================================

    /**
     * @notice Emitted on accruals.
     * @param platformFees amount of shares minted as platform fees this accrual
     * @param performanceFees amount of shares minted as performance fees this accrual
     * @param yield amount of assets accrued as yield that will be distributed over this accrual period
     */
    event Accrual(uint256 platformFees, uint256 performanceFees, uint256 yield);

    /**
     * @notice Accrue yield, platform fees, and performance fees.
     * @dev Since this is the function responsible for distributing yield to shareholders and
     *      updating the cellar's balance, it is important to make sure it gets called regularly.
     */
    function accrue() external;

    // ========================================= POSITION LOGIC =========================================
    /**
     * @notice Emitted on deposit to Aave.
     * @param position the address of the position
     * @param assets the amount of assets to deposit
     */
    event DepositIntoPosition(address indexed position, uint256 assets);

    /**
     * @notice Emitted on withdraw from Aave.
     * @param position the address of the position
     * @param assets the amount of assets to withdraw
     */
    event WithdrawFromPosition(address indexed position, uint256 assets);

    /**
     * @notice Emitted upon entering assets into the current position on Aave.
     * @param position the address of the asset being pushed into the current position
     * @param assets amount of assets being pushed
     */
    event EnterPosition(address indexed position, uint256 assets);

    /**
     * @notice Emitted upon exiting assets from the current position on Aave.
     * @param position the address of the asset being pulled from the current position
     * @param assets amount of assets being pulled
     */
    event ExitPosition(address indexed position, uint256 assets);

    /**
     * @notice Emitted on rebalance of Aave poisition.
     * @param oldAsset the address of the asset for the old position
     * @param newAsset the address of the asset for the new position
     * @param assets the amount of the new assets cellar has after rebalancing
     */
    event Rebalance(address indexed oldAsset, address indexed newAsset, uint256 assets);

    function enterPosition() external;

    function enterPosition(uint256 assets) external;

    function exitPosition() external;

    function exitPosition(uint256 assets) external;

    function rebalance(
        address[9] memory route,
        uint256[3][4] memory swapParams,
        uint256 minAssetsOut
    ) external;

    // ========================================= REINVEST LOGIC =========================================

    /**
     * @notice Emitted upon claiming rewards and beginning cooldown period to unstake them.
     * @param rewards amount of rewards that were claimed
     */
    event ClaimAndUnstake(uint256 rewards);

    /**
     * @notice Emitted upon reinvesting rewards into the current position.
     * @param token the address of the asset rewards were swapped to
     * @param rewards amount of rewards swapped to be reinvested
     * @param assets amount of assets received from swapping rewards
     */
    event Reinvest(address indexed token, uint256 rewards, uint256 assets);

    function claimAndUnstake() external returns (uint256 rewards);

    function reinvest(uint256 minAssetsOut) external;

    // =========================================== FEES LOGIC ===========================================

    /**
     * @notice Emitted when platform fees are send to the Sommelier chain.
     * @param feesInSharesRedeemed amount of fees redeemed for assets to send
     * @param feesInAssetsSent amount of assets fees were redeemed for that were sent
     */
    event SendFees(uint256 feesInSharesRedeemed, uint256 feesInAssetsSent);

    function sendFees() external;

    // ========================================= RECOVERY LOGIC =========================================

    /**
     * @notice Emitted when tokens accidentally sent to cellar are recovered.
     * @param token the address of the token
     * @param to the address sweeped tokens were transferred to
     * @param amount amount transferred out
     */
    event Sweep(address indexed token, address indexed to, uint256 amount);

    function sweep(ERC20 token, address to) external;
}
