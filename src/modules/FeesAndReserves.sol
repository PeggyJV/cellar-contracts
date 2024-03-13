// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC20, SafeTransferLib, Math, Address } from "src/base/Cellar.sol";
import { IGravity } from "src/interfaces/external/IGravity.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { Owned } from "@solmate/auth/Owned.sol";

/**
 * @title Fees And Reserves
 * @notice Allows strategists to move yield in/out of reserves in order to better manage their strategy.
 * @notice Allows strategists to take performance and management fees on their cellars.
 * @author crispymangoes
 * @dev Important Safety Considerations
 *      - There should be no way for strategists to call `performUpkeep` DURING a rebalance.
 *      - All public mutative functions run reentrancy checks.
 *      - Important meta data, like a Cellar's asset is saved in this contract
 */
contract FeesAndReserves is Owned, AutomationCompatibleInterface, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    // ========================================= STRUCTS =========================================

    /**
     * @notice Stores meta data needed to calculate a calling cellars earned fees.
     * @dev Store calling Cellars meta data in this contract to help mitigate malicious external contracts
     *         attempting to break logic by illogically changing meta data values.
     * @param reserveAsset ERC20 asset Cellar does all its accounting in
     * @param managementFee Fee charged for managing a Cellar's assets
     *        - Based off basis points, so 100% would be 1e4
     * @param timestamp The last time this cellar had it's fees calculated
     * @param reserves The amount of `reserveAsset` a Cellar has available to it
     * @param exactHighWatermark High Watermark normalized to 27 decimals
     * @param totalAssets Stored total assets
     *        - When calculating fees this value is compared against the current Total Assets, and the minimum value is used
     * @param feesOwed The amount of fees this cellar has accumulated from both performance and management fees
     * @param cellarDecimals Number of decimals Cellar Shares have
     * @param reserveAssetDecimals Number of decimals the `reserveAsset` has
     * @param performanceFee Fee charged based off a cellar share price growth
     *        - Based off basis points, so 100% would be 1e4
     */
    struct MetaData {
        ERC20 reserveAsset;
        uint32 managementFee;
        uint64 timestamp;
        uint256 reserves;
        uint256 exactHighWatermark;
        uint256 totalAssets;
        uint256 feesOwed;
        uint8 cellarDecimals;
        uint8 reserveAssetDecimals;
        uint32 performanceFee;
    }

    /**
     * @notice Pending meta data values that are used to update a Cellar's actual MetaData
     *         once fees have been calculated using the old values.
     */
    struct PendingMetaData {
        uint32 pendingManagementFee;
        uint32 pendingPerformanceFee;
    }

    /**
     * @notice `performUpkeep` input struct.
     * @dev This contract leverages Chainlink secure offchain computation by calculating
     *      - fee earned
     *      - current exact share price normalized to 27 decimals
     *      - total assets
     *      - timestamp these calcualtions were performed
     *      Off chain so that Chainlink Automation calls are cheaper
     */
    struct PerformInput {
        Cellar cellar;
        uint256 feeEarned;
        uint256 exactSharePrice; // Normalized to 27 decimals
        uint256 totalAssets;
        uint64 timestamp;
    }

    /**
     * @notice Struct stores data used to change how an upkeep behaves.
     * @param frequency The amount of time that must pass since the last upkeep before upkeep can be done again
     * @param maxGas The max gas price strategist is willing to pay for an upkeep
     * @param lasUpkeepTime The timestamp of the last upkeep
     */
    struct UpkeepData {
        uint64 frequency; // Frequency to log fees
        uint64 maxGas; // Max gas price owner is willing to pay to log fees.
        uint64 lastUpkeepTime; // The last time an upkeep was ran.
    }

    // ========================================= GLOBAL STATE =========================================

    uint8 public constant BPS_DECIMALS = 4;
    uint256 public constant PRECISION_MULTIPLIER = 1e27;
    uint8 public constant NORMALIZED_DECIMALS = 27;
    uint256 public constant SECONDS_IN_A_YEAR = 365 days;
    uint256 public constant MAX_PERFORMANCE_FEE = 3 * 10 ** (BPS_DECIMALS - 1); // 30%
    uint256 public constant MAX_MANAGEMENT_FEE = 1 * 10 ** (BPS_DECIMALS - 1); // 10%

    /**
     * @notice Cosmos address where protocol fees are sent.
     */
    bytes32 public constant FEES_DISTRIBUTOR = hex"000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55";

    /**
     * @notice Maps a cellar to its pending meta data.
     */
    mapping(Cellar => PendingMetaData) public pendingMetaData;

    /**
     * @notice Maps a cellar to its upkeep data.
     */
    mapping(Cellar => UpkeepData) public cellarToUpkeepData;

    /**
     * @notice Maps a cellar to its meta data.
     */
    mapping(Cellar => MetaData) public metaData;

    /**
     * @notice Maps a cellar to the amount of fees it will claim on `sendFees` call.
     */
    mapping(Cellar => uint256) public feesReadyForClaim;

    /**
     * @notice Chainlink Fast Gas Feed for current network.
     * @notice For mainnet use 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C.
     */
    address public ETH_FAST_GAS_FEED;

    /**
     * @notice Whether or not the contract is shutdown in case of an emergency.
     */
    bool public isShutdown;

    //============================== MODIFIERS ===============================

    /**
     * @notice Make sure a caller has been properly setup.
     */
    modifier checkCallerIsSetup() {
        if (
            address(metaData[Cellar(msg.sender)].reserveAsset) == address(0) ||
            metaData[Cellar(msg.sender)].exactHighWatermark == 0
        ) revert FeesAndReserves__CellarNotSetup();
        _;
    }

    /**
     * @notice Prevent a function from being called during a shutdown.
     */
    modifier whenNotShutdown() {
        if (isShutdown) revert FeesAndReserves__ContractShutdown();

        _;
    }

    //============================== EVENTS ===============================

    event ShutdownChanged(bool isShutdown);
    event HighWatermarkReset(address cellar);
    event FeesPrepared(address cellar, uint256 amount, uint256 totalFeesReady);
    event AssetsWithdrawnFromReserves(address cellar, uint256 amount);
    event AssetsAddedToReserves(address cellar, uint256 amount);
    event ManagementFeeChanged(address cellar, uint32 newFee);
    event PerformanceFeeChanged(address cellar, uint32 newFee);
    event FeesSent(address cellar);

    //============================== ERRORS ===============================

    error FeesAndReserves__ContractShutdown();
    error FeesAndReserves__ContractNotShutdown();
    error FeesAndReserves__CellarNotSetup();
    error FeesAndReserves__CellarAlreadySetup();
    error FeesAndReserves__InvalidCut();
    error FeesAndReserves__NothingToPayout();
    error FeesAndReserves__NotEnoughReserves();
    error FeesAndReserves__NotEnoughFeesOwed();
    error FeesAndReserves__InvalidPerformanceFee();
    error FeesAndReserves__InvalidManagementFee();
    error FeesAndReserves__InvalidReserveAsset();
    error FeesAndReserves__InvalidUpkeep();
    error FeesAndReserves__UpkeepTimeCheckFailed();
    error FeesAndReserves__InvalidResetPercent();

    //============================== IMMUTABLES ===============================

    /**
     * @notice For ETH Mainnet this is the actual Gravity Bridge.
     * @notice If on another L2, this will be a fee transfer contract
     *         that implements `sendToCosmos`.
     */
    IGravity public immutable gravityBridge;

    /**
     * @notice Chainlink's Automation Registry contract address.
     * @notice For mainnet use 0x02777053d6764996e594c3E88AF1D58D5363a2e6.
     */
    address public immutable AUTOMATION_REGISTRY;

    constructor(address _gravityBridge, address automationRegistry, address fastGasFeed) Owned(msg.sender) {
        gravityBridge = IGravity(_gravityBridge);
        AUTOMATION_REGISTRY = automationRegistry;
        ETH_FAST_GAS_FEED = fastGasFeed;
    }

    //============================================ onlyOwner Functions ===========================================

    /**
     * @notice Shutdown the cellar. Used in an emergency or if the cellar has been deprecated.
     */
    function initiateShutdown() external whenNotShutdown onlyOwner {
        isShutdown = true;

        emit ShutdownChanged(true);
    }

    /**
     * @notice Restart the cellar.
     */
    function liftShutdown() external onlyOwner {
        if (!isShutdown) revert FeesAndReserves__ContractNotShutdown();
        isShutdown = false;

        emit ShutdownChanged(false);
    }

    /**
     * @notice Allows owner to set a new gas feed.
     * @notice Can be set to zero address to skip gas check.
     */
    function setGasFeed(address gasFeed) external onlyOwner {
        ETH_FAST_GAS_FEED = gasFeed;
    }

    /**
     * @notice Allows owner to reset a Cellar's Share Price High Watermark.
     * @dev Resetting HWM will zero out all fees owed.
     * @param resetPercent Number between 0 bps and 10,000 bps.
     *                     0 - HWM does not change at all
     *                10,000 - HWM is fully reset to current share price
     */
    function resetHWM(Cellar cellar, uint32 resetPercent) external onlyOwner {
        if (resetPercent == 0 || resetPercent > 10 ** BPS_DECIMALS) revert FeesAndReserves__InvalidResetPercent();
        MetaData storage data = metaData[cellar];

        uint256 totalAssets = cellar.totalAssets();

        uint256 totalSupply = cellar.totalSupply();
        // Calculate Share price normalized to 27 decimals.
        uint256 exactSharePrice = totalAssets.changeDecimals(data.reserveAssetDecimals, NORMALIZED_DECIMALS).mulDivDown(
            10 ** data.cellarDecimals,
            totalSupply
        );

        data.exactHighWatermark =
            data.exactHighWatermark -
            (data.exactHighWatermark - exactSharePrice).mulDivDown(resetPercent, 10 ** BPS_DECIMALS);

        // Reset fees earned.
        data.feesOwed = 0;

        emit HighWatermarkReset(address(cellar));
    }

    //============================== Strategist Functions(called through adaptors) ===============================

    /**
     * @notice Setup function called when a new cellar begins using this contract
     */
    function setupMetaData(uint32 managementFee, uint32 performanceFee) external whenNotShutdown nonReentrant {
        Cellar cellar = Cellar(msg.sender);

        if (address(metaData[cellar].reserveAsset) != address(0)) revert FeesAndReserves__CellarAlreadySetup();
        if (performanceFee > MAX_PERFORMANCE_FEE) revert FeesAndReserves__InvalidPerformanceFee();
        if (managementFee > MAX_MANAGEMENT_FEE) revert FeesAndReserves__InvalidManagementFee();

        ERC20 reserveAsset = cellar.asset();
        if (address(reserveAsset) == address(0)) revert FeesAndReserves__InvalidReserveAsset();
        uint8 cellarDecimals = cellar.decimals();
        uint8 reserveAssetDecimals = reserveAsset.decimals();

        metaData[cellar] = MetaData({
            reserveAsset: reserveAsset,
            managementFee: managementFee,
            timestamp: uint64(block.timestamp),
            reserves: 0,
            exactHighWatermark: 0,
            totalAssets: 0,
            feesOwed: 0,
            cellarDecimals: cellarDecimals,
            reserveAssetDecimals: reserveAssetDecimals,
            performanceFee: performanceFee
        });

        // Update pending values to match actual.
        pendingMetaData[cellar].pendingManagementFee = managementFee;
        pendingMetaData[cellar].pendingPerformanceFee = performanceFee;
    }

    uint64 public constant MINIMUM_UPKEEP_FREQUENCY = 3_600;

    error FeesAndReserves__MinimumUpkeepFrequencyNotMet();

    /**
     * @notice Strategist callable, value is immediately used.
     */
    function changeUpkeepFrequency(uint64 newFrequency) external nonReentrant {
        if (newFrequency < MINIMUM_UPKEEP_FREQUENCY) revert FeesAndReserves__MinimumUpkeepFrequencyNotMet();
        Cellar cellar = Cellar(msg.sender);

        cellarToUpkeepData[cellar].frequency = newFrequency;
    }

    /**
     * @notice Strategist callable, value is immediately used.
     */
    function changeUpkeepMaxGas(uint64 newMaxGas) external nonReentrant {
        Cellar cellar = Cellar(msg.sender);

        cellarToUpkeepData[cellar].maxGas = newMaxGas;
    }

    /**
     * @notice Strategist callable, value is only used after
     *         performUpkeep is ran for the cellar.
     */
    function updatePerformanceFee(uint32 performanceFee) external nonReentrant checkCallerIsSetup {
        Cellar cellar = Cellar(msg.sender);
        if (performanceFee > MAX_PERFORMANCE_FEE) revert FeesAndReserves__InvalidPerformanceFee();

        PendingMetaData storage data = pendingMetaData[cellar];

        data.pendingPerformanceFee = performanceFee;

        emit PerformanceFeeChanged(address(cellar), performanceFee);
    }

    /**
     * @notice Strategist callable, value is only used after
     *         performUpkeep is ran for the cellar.
     */
    function updateManagementFee(uint32 managementFee) external nonReentrant checkCallerIsSetup {
        Cellar cellar = Cellar(msg.sender);
        if (managementFee > MAX_MANAGEMENT_FEE) revert FeesAndReserves__InvalidManagementFee();

        PendingMetaData storage data = pendingMetaData[cellar];

        data.pendingManagementFee = managementFee;

        emit ManagementFeeChanged(address(cellar), managementFee);
    }

    /**
     * @notice Allows strategists to freely move assets into reserves.
     */
    function addAssetsToReserves(uint256 amount) external whenNotShutdown nonReentrant checkCallerIsSetup {
        Cellar cellar = Cellar(msg.sender);
        MetaData storage data = metaData[cellar];

        data.reserves += amount;
        data.reserveAsset.safeTransferFrom(msg.sender, address(this), amount);

        emit AssetsAddedToReserves(address(cellar), amount);
    }

    /**
     * @notice Allows strategists to freely move assets from reserves.
     */
    function withdrawAssetsFromReserves(uint256 amount) external nonReentrant checkCallerIsSetup {
        Cellar cellar = Cellar(msg.sender);
        MetaData storage data = metaData[cellar];

        // If amount is type(uint256).max caller is trying to withdraw all reserves.
        if (amount == type(uint256).max) amount = data.reserves;

        if (amount > data.reserves) revert FeesAndReserves__NotEnoughReserves();

        data.reserves -= amount;
        data.reserveAsset.safeTransfer(msg.sender, amount);
        emit AssetsWithdrawnFromReserves(address(cellar), amount);
    }

    /**
     * @dev Moves assets from reserves into `feesReadyForClaim`.
     * @param amount the amount of reserves to set aside for fees.
     */
    function prepareFees(uint256 amount) external nonReentrant checkCallerIsSetup {
        Cellar cellar = Cellar(msg.sender);
        MetaData storage data = metaData[cellar];

        // If amount is type(uint256).max caller is trying to prepare max possible fees owed.
        if (amount == type(uint256).max) amount = data.feesOwed.min(data.reserves);

        if (amount > data.feesOwed) revert FeesAndReserves__NotEnoughFeesOwed();
        if (amount > data.reserves) revert FeesAndReserves__NotEnoughReserves();

        // Reduce fees owed and reduce reserves.
        data.feesOwed -= amount;
        data.reserves -= amount;

        feesReadyForClaim[cellar] += amount;

        emit FeesPrepared(address(cellar), amount, feesReadyForClaim[cellar]);
    }

    //============================== Public Functions(called by anyone) ===============================

    /**
     * @notice Takes assets stored in `feesReadyForClaim`, splits it up between strategist and gravity bridge.
     */
    function sendFees(Cellar cellar) external nonReentrant {
        MetaData storage data = metaData[cellar];

        if (address(metaData[cellar].reserveAsset) == address(0)) revert FeesAndReserves__CellarNotSetup();

        uint256 payout = feesReadyForClaim[cellar];
        if (payout == 0) revert FeesAndReserves__NothingToPayout();
        // Zero out balance before any external calls.
        feesReadyForClaim[cellar] = 0;

        // Get the fee split, and payout address from the cellar, even thought the fee split is intended for platform fees
        (uint64 strategistPlatformCut, , , address strategistPayout) = cellar.feeData();

        // Make sure `strategistPlatformCut` is logical.
        if (strategistPlatformCut > 1e18) revert FeesAndReserves__InvalidCut();

        uint256 strategistCut = payout.mulDivDown(strategistPlatformCut, 1e18);
        uint256 sommCut = payout - strategistCut;

        // Send assets to strategist.
        data.reserveAsset.safeTransfer(strategistPayout, strategistCut);

        data.reserveAsset.safeApprove(address(gravityBridge), sommCut);
        gravityBridge.sendToCosmos(address(data.reserveAsset), FEES_DISTRIBUTOR, sommCut);
        emit FeesSent(address(cellar));
    }

    /**
     * @notice CheckUpkeep runs several checks on proposed cellars.
     *         - Checks that the Cellar has called setup function.
     *         - Checks that gas is reasonable.
     *         - Checks that enough time has passed.
     *         - Checks that the cellar has pending fees, or that it needs to finish setup.
     */
    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData) {
        if (isShutdown) return (false, abi.encode(0));

        Cellar[] memory cellars = abi.decode(checkData, (Cellar[]));
        uint256 currentGasPrice = uint256(IChainlinkAggregator(ETH_FAST_GAS_FEED).latestAnswer());

        for (uint256 i; i < cellars.length; ++i) {
            // Skip cellars that are not set up yet.
            if (address(metaData[cellars[i]].reserveAsset) == address(0)) continue;

            UpkeepData memory data = cellarToUpkeepData[cellars[i]];

            // Skip cellars that have not set an upkeep frequency.
            if (data.frequency == 0) continue;

            // Skip cellar if gas is too high.
            if (currentGasPrice > data.maxGas) continue;

            // Skip cellar if not enough time has passed.
            if (block.timestamp < (data.lastUpkeepTime + data.frequency)) continue;

            PerformInput memory input = _calculateFees(cellars[i]);
            // Only log fees if there are fees to be earned, or if we need to finish setup.
            if (input.feeEarned > 0 || metaData[cellars[i]].exactHighWatermark == 0) {
                upkeepNeeded = true;
                performData = abi.encode(input);
                break;
            }
        }
    }

    /**
     * @notice PerformUpkeep will trust `performData` input if the caller is `AUTOMATION_REGISTRY` otherwise the input is recalcualted.
     * @dev If cellar is not setup, this function reverts.
     * @dev If not enough time has passed, the cellar does not have its fees calculated.
     * @dev If cellar has pending values that differ from current stored values, they are updated.
     * @dev We also update stored totalAssets, and timestamp when any fees are earned, so that future fee calculations are more accurate.
     */
    function performUpkeep(bytes calldata performData) external whenNotShutdown nonReentrant {
        PerformInput memory performInput = abi.decode(performData, (PerformInput));
        UpkeepData storage upkeepData = cellarToUpkeepData[performInput.cellar];
        if (msg.sender != AUTOMATION_REGISTRY) {
            // Do not trust callers perform input data.
            Cellar target = performInput.cellar;

            if (address(metaData[target].reserveAsset) == address(0)) revert FeesAndReserves__CellarNotSetup();
            performInput = _calculateFees(target);
        } else {
            if (address(metaData[performInput.cellar].reserveAsset) == address(0))
                revert FeesAndReserves__CellarNotSetup();
            // Make sure performInput is not stale.
            if (upkeepData.lastUpkeepTime > performInput.timestamp) revert FeesAndReserves__UpkeepTimeCheckFailed();
        }

        MetaData storage data = metaData[performInput.cellar];
        // If not enough time has passed since the last upkeep, revert.
        if (upkeepData.frequency == 0 || block.timestamp < (upkeepData.lastUpkeepTime + upkeepData.frequency))
            revert FeesAndReserves__UpkeepTimeCheckFailed();
        // Check if fees were earned and update data if so.
        if (performInput.feeEarned > 0) {
            data.feesOwed += performInput.feeEarned;
            data.timestamp = performInput.timestamp;
            data.totalAssets = performInput.totalAssets;
            upkeepData.lastUpkeepTime = uint64(block.timestamp);
            // Only update the HWM if current share price is greater than it.
            if (performInput.exactSharePrice > data.exactHighWatermark)
                data.exactHighWatermark = performInput.exactSharePrice;
        } else if (data.exactHighWatermark == 0) {
            // Need to set up cellar by setting HWM, TA, and timestamp.
            data.exactHighWatermark = performInput.exactSharePrice;
            data.timestamp = performInput.timestamp;
            data.totalAssets = performInput.totalAssets;
            upkeepData.lastUpkeepTime = uint64(block.timestamp);
        } else revert FeesAndReserves__InvalidUpkeep();
        // Update pending values if need be.
        PendingMetaData storage pending = pendingMetaData[performInput.cellar];
        if (data.managementFee != pending.pendingManagementFee) data.managementFee = pending.pendingManagementFee;
        if (data.performanceFee != pending.pendingPerformanceFee) data.performanceFee = pending.pendingPerformanceFee;
    }

    /**
     * @notice Calculates fees owed, by comparing current state, to previous state when `_calculateFees` was last called.
     * @dev If stored High Watermark is zero, then no fees are calculated, because setup must be finished.
     */
    function _calculateFees(Cellar cellar) internal view returns (PerformInput memory input) {
        MetaData memory data = metaData[cellar];

        // Setup cellar in input, so that performUpkeep can still run update pending values.
        input.cellar = cellar;

        // Save values in
        input.totalAssets = cellar.totalAssets();
        input.timestamp = uint64(block.timestamp);

        uint256 totalSupply = cellar.totalSupply();
        // Calculate Share price normalized to 27 decimals.
        input.exactSharePrice = input
            .totalAssets
            .changeDecimals(data.reserveAssetDecimals, NORMALIZED_DECIMALS)
            .mulDivDown(10 ** data.cellarDecimals, totalSupply);

        if (data.exactHighWatermark > 0) {
            // Calculate Management Fees owed.
            uint256 elapsedTime = block.timestamp - data.timestamp;
            if (data.managementFee > 0 && elapsedTime > 0) {
                input.feeEarned += input
                    .totalAssets
                    .min(data.totalAssets)
                    .mulDivDown(data.managementFee, 10 ** BPS_DECIMALS)
                    .mulDivDown(elapsedTime, SECONDS_IN_A_YEAR);
            }

            // Calculate Performance Fees owed.
            if (input.exactSharePrice > data.exactHighWatermark) {
                input.feeEarned += input
                    .totalAssets
                    .min(data.totalAssets)
                    .mulDivDown(input.exactSharePrice - data.exactHighWatermark, PRECISION_MULTIPLIER)
                    .mulDivDown(data.performanceFee, 10 ** BPS_DECIMALS);
            }
        } // else Cellar needs to finish its setup..
        // This will trigger `performUpkeep` to save the totalAssets, exactHighWatermark, and timestamp.
    }

    function getMetaData(Cellar cellar) external view returns (MetaData memory) {
        return metaData[cellar];
    }
}
