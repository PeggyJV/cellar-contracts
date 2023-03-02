// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Registry, Owned, ERC20, SafeTransferLib, Math, Address, IGravity } from "src/base/Cellar.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";

import { console } from "@forge-std/Test.sol";

contract FeesAndReserves is Owned, AutomationCompatibleInterface, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    uint8 public constant BPS_DECIMALS = 4;
    uint256 public constant PRECISION_MULTIPLIER = 1e27;
    uint8 public constant NORMALIZED_DECIMALS = 27;
    uint256 public constant SECONDS_IN_A_YEAR = 365 days;
    uint256 public constant MAX_PERFORMANCE_FEE = 3 * 10**(BPS_DECIMALS - 1); // 30%

    /**
     * @notice Store calling Cellars meta data in this contract to help mitigate malicous external contracts
     *         attempting to break logic by illogically changing meta data values.
     */
    struct MetaData {
        ERC20 reserveAsset; // Same as cellars accounting asset
        uint32 managementFee;
        uint64 timestamp; // Timestamp fees were last logged
        uint256 reserves; // Total amount of `reserveAsset` cellar has in reserves
        uint256 exactHighWatermark; // The Cellars Share Price High Water Mark Normalized to 27 decimals
        uint256 totalAssets; // The Cellars totalAssets with 18 decimals
        uint256 feesOwed; // The performance fees cellar has earned, to be paid out
        uint8 cellarDecimals;
        uint8 reserveAssetDecimals;
        uint32 performanceFee;
    }

    /**
     * @notice Pending meta data values that are used to update a Cellar's actual MetaData once fees have been calculated using the old values.
     */
    struct PendingMetaData {
        uint32 pendingManagementFee;
        uint32 pendingPerformanceFee;
    }

    struct PerformInput {
        Cellar cellar;
        uint256 feeEarned;
        uint256 exactSharePrice; // Normalized to 27 decimals
        uint256 totalAssets;
        uint64 timestamp;
    }

    mapping(Cellar => PendingMetaData) public pendingMetaData;

    struct UpkeepData {
        uint64 frequency; // Frequency to log fees
        uint64 maxGas; // Max gas price owner is willing to pay to log fees.
        uint64 lastUpkeepTime; // The last time an upkeep was ran.
    }

    mapping(Cellar => UpkeepData) public cellarToUpkeepData;

    mapping(Cellar => MetaData) public metaData;

    function getMetaData(Cellar cellar) external view returns (MetaData memory) {
        return metaData[cellar];
    }

    mapping(Cellar => uint256) public feesReadyForClaim;

    /**
     * @notice Chainlink's Automation Registry contract address.
     */
    address public automationRegistry = 0x02777053d6764996e594c3E88AF1D58D5363a2e6;

    /**
     * @notice Chainlink Fast Gas Feed for ETH Mainnet.
     */
    address public ETH_FAST_GAS_FEED = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    constructor() Owned(msg.sender) {}

    // =========================================== EMERGENCY LOGIC ===========================================

    /**
     * @notice Emitted when FeesAndReserves emergency state is changed.
     * @param isShutdown whether the cellar is shutdown
     */
    event ShutdownChanged(bool isShutdown);

    /**
     * @notice Attempted action was prevented due to contract being shutdown.
     */
    error FeesAndReserves__ContractShutdown();

    /**
     * @notice Attempted action was prevented due to contract not being shutdown.
     */
    error FeesAndReserves__ContractNotShutdown();

    /**
     * @notice Whether or not the contract is shutdown in case of an emergency.
     */
    bool public isShutdown;

    /**
     * @notice Prevent a function from being called during a shutdown.
     */
    modifier whenNotShutdown() {
        if (isShutdown) revert FeesAndReserves__ContractShutdown();

        _;
    }

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

    //============================================ onlyOwner Functions ===========================================

    /**
     * @notice Allows owner to update the Automation Registry.
     * @dev In rare cases, Chainlink's registry CAN change.
     */
    function setAutomationRegistry(address newRegistry) external onlyOwner {
        automationRegistry = newRegistry;
    }

    /**
     * @notice Allows owner to set a new gas feed.
     * @notice Can be set to zero address to skip gas check.
     */
    function setGasFeed(address gasFeed) external onlyOwner {
        ETH_FAST_GAS_FEED = gasFeed;
    }

    event HighWatermarkReset(address cellar);

    function resetHWM(Cellar cellar) external onlyOwner {
        MetaData storage data = metaData[cellar];

        uint256 totalAssets = cellar.totalAssets();

        uint256 totalSupply = cellar.totalSupply();
        // Calculate Share price normalized to 27 decimals.
        uint256 exactSharePrice = totalAssets.changeDecimals(data.reserveAssetDecimals, NORMALIZED_DECIMALS).mulDivDown(
            10**data.cellarDecimals,
            totalSupply
        );

        data.exactHighWatermark = exactSharePrice;

        emit HighWatermarkReset(address(cellar));
    }

    //============================== Strategist Functions(called through adaptors) ===============================
    /**
     * @notice These functions are callable by anyone, but are intended to be called by strategists through their Cellars `callOnAdaptor`.
     *         To help reduce attack vectors, several mitigations have been added:
     *         - important meta data, like a Cellar's asset is saved in this contract
     *         - all public mutative functions have reentrancy protection
     */
    // Strategist function
    function setupMetaData(uint32 managementFee, uint32 performanceFee) external nonReentrant {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) != address(0)) revert("Cellar already setup.");
        if (performanceFee > MAX_PERFORMANCE_FEE) revert("Large Fee.");
        ERC20 reserveAsset = cellar.asset();
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

    /**
     * @notice Strategist callable, value is immediately used.
     */
    function changeUpkeepFrequency(uint64 newFrequency) external nonReentrant {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");

        cellarToUpkeepData[cellar].frequency = newFrequency;
    }

    /**
     * @notice Strategist callable, value is immediatley used.
     */
    function changeUpkeepMaxGas(uint64 newMaxGas) external nonReentrant {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");

        cellarToUpkeepData[cellar].maxGas = newMaxGas;
    }

    event PerformanceFeeChanged(address cellar, uint32 newFee);

    // TODO add limits to these.
    /**
     * @notice Strategist callable, value is only used after
     *         performUpkeep is ran for the cellar.
     */
    function updatePerformanceFee(uint32 performanceFee) external nonReentrant {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");

        PendingMetaData storage data = pendingMetaData[cellar];

        data.pendingPerformanceFee = performanceFee;

        emit PerformanceFeeChanged(address(cellar), performanceFee);
    }

    event ManagementFeeChanged(address cellar, uint32 newFee);

    /**
     * @notice Strategist callable, value is only used after
     *         performUpkeep is ran for the cellar.
     */
    function updateManagementFee(uint32 managementFee) external nonReentrant {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");

        PendingMetaData storage data = pendingMetaData[cellar];

        data.pendingManagementFee = managementFee;

        emit ManagementFeeChanged(address(cellar), managementFee);
    }

    event AssetsAddedToReserves(address cellar, uint256 amount);

    /**
     * @notice Allows strategists to freely move assets into reserves.
     */
    function addAssetsToReserves(uint256 amount) external whenNotShutdown nonReentrant {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");
        MetaData storage data = metaData[cellar];

        data.reserves += amount;
        data.reserveAsset.safeTransferFrom(msg.sender, address(this), amount);

        emit AssetsAddedToReserves(address(cellar), amount);
    }

    event AssetsWithdrawnFromReserves(address cellar, uint256 amount);

    /**
     * @notice Allows strategists to freely move assets from reserves.
     */
    function withdrawAssetsFromReserves(uint256 amount) external nonReentrant {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");
        MetaData storage data = metaData[cellar];

        if (amount > data.reserves) revert("Not enough reserves.");

        data.reserves -= amount;
        data.reserveAsset.safeTransfer(msg.sender, amount);
        emit AssetsWithdrawnFromReserves(address(cellar), amount);
    }

    event FeesPrepared(address cellar, uint256 amount, uint256 totalFeesReady);

    /**
     * @dev removes assets from reserves, so that `sendFees` can be called.
     * @param amount the amount of reserves to set aside for fees.
     */
    function prepareFees(uint256 amount) external nonReentrant {
        Cellar cellar = Cellar(msg.sender);
        MetaData storage data = metaData[cellar];

        if (address(data.reserveAsset) == address(0)) revert("Cellar not setup.");

        if (amount > data.feesOwed) revert("Not enough fees owed.");
        if (amount > data.reserves) revert("Not enough reserves.");

        // Reduce fees owed and reduce reserves.
        data.feesOwed -= amount;
        data.reserves -= amount;

        feesReadyForClaim[cellar] += amount;

        emit FeesPrepared(address(cellar), amount, feesReadyForClaim[cellar]);
    }

    //============================== Public Functions(called by anyone) ===============================

    event FeesSent(address cellar);

    function sendFees(Cellar cellar) external nonReentrant {
        MetaData storage data = metaData[cellar];

        if (address(data.reserveAsset) == address(0)) revert("Cellar not setup.");
        uint256 payout = feesReadyForClaim[cellar];
        if (payout == 0) revert("Nothing to payout.");
        // Zero out balance before any external calls.
        feesReadyForClaim[cellar] = 0;

        Registry registry = cellar.registry();

        // Get the registry, and fee split from the cellar, even thought the fee split is intended for platform fees
        // but if we make a custom fee split, gov needs to be able to update this...
        (uint64 strategistPlatformCut, , , address strategistPayout) = cellar.feeData();

        uint256 strategistCut = payout.mulDivDown(strategistPlatformCut, 1e18);
        uint256 sommCut = payout - strategistCut;

        // Send assets to strategist.
        data.reserveAsset.safeTransfer(strategistPayout, strategistCut);

        IGravity gravityBridge = IGravity(registry.getAddress(0));
        data.reserveAsset.safeApprove(address(gravityBridge), sommCut);
        gravityBridge.sendToCosmos(address(data.reserveAsset), registry.feesDistributor(), sommCut);
        emit FeesSent(address(cellar));
    }

    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData) {
        if (isShutdown) return (false, abi.encode(0));

        Cellar[] memory cellars = abi.decode(checkData, (Cellar[]));
        uint256 currentGasPrice = uint256(IChainlinkAggregator(ETH_FAST_GAS_FEED).latestAnswer());

        PerformInput[] memory performInput = new PerformInput[](cellars.length);
        for (uint256 i; i < cellars.length; ++i) {
            // Skip cellars that are not set up yet.
            if (address(metaData[cellars[i]].reserveAsset) == address(0)) continue;
            UpkeepData memory data = cellarToUpkeepData[cellars[i]];
            // Skip cellar if gas is too high.
            if (currentGasPrice > data.maxGas) continue;
            // Skip cellar if not enough time has passed.
            if (block.timestamp < (data.lastUpkeepTime + data.frequency)) continue;

            PerformInput memory input = _calculateFees(cellars[i]);
            // Only log fees if there are fees to be earned.
            if (input.feeEarned > 0 || metaData[cellars[i]].exactHighWatermark == 0) {
                upkeepNeeded = true;
                performInput[i] = input;
            }
        }

        if (upkeepNeeded) performData = abi.encode(performInput);
    }

    function performUpkeep(bytes calldata performData) external whenNotShutdown nonReentrant {
        PerformInput[] memory performInput = abi.decode(performData, (PerformInput[]));
        if (msg.sender != automationRegistry) {
            // Do not trust callers perform input data.
            for (uint256 i; i < performInput.length; ++i) {
                Cellar target = performInput[i].cellar;

                if (address(metaData[target].reserveAsset) == address(0)) revert("Cellar not setup.");
                performInput[i] = _calculateFees(target);
            }
        }
        for (uint256 i; i < performInput.length; ++i) {
            if (address(metaData[performInput[i].cellar].reserveAsset) == address(0)) revert("Cellar not setup.");
            UpkeepData storage upkeepData = cellarToUpkeepData[performInput[i].cellar];
            MetaData storage data = metaData[performInput[i].cellar];
            if (block.timestamp >= (upkeepData.lastUpkeepTime + upkeepData.frequency)) {
                // Check if fees were earned and update data if so.
                if (performInput[i].feeEarned > 0) {
                    data.feesOwed += performInput[i].feeEarned;
                    data.exactHighWatermark = performInput[i].exactSharePrice;
                    data.timestamp = performInput[i].timestamp;
                    data.totalAssets = performInput[i].totalAssets;
                    upkeepData.lastUpkeepTime = uint64(block.timestamp);
                } else if (data.exactHighWatermark == 0) {
                    // Need to set up cellar by setting HWM, TA, and timestamp.
                    data.exactHighWatermark = performInput[i].exactSharePrice;
                    data.timestamp = performInput[i].timestamp;
                    data.totalAssets = performInput[i].totalAssets;
                    upkeepData.lastUpkeepTime = uint64(block.timestamp);
                }
            }

            // Update pending values if need be.
            PendingMetaData storage pending = pendingMetaData[performInput[i].cellar];
            if (data.managementFee != pending.pendingManagementFee) data.managementFee = pending.pendingManagementFee;
            if (data.performanceFee != pending.pendingPerformanceFee)
                data.performanceFee = pending.pendingPerformanceFee;
        }
    }

    function _calculateFees(Cellar cellar) internal view returns (PerformInput memory input) {
        MetaData memory data = metaData[cellar];

        // Save values in
        input.totalAssets = cellar.totalAssets();
        input.timestamp = uint64(block.timestamp);

        uint256 totalSupply = cellar.totalSupply();
        // Calculate Share price normalized to 27 decimals.
        input.exactSharePrice = input
            .totalAssets
            .changeDecimals(data.reserveAssetDecimals, NORMALIZED_DECIMALS)
            .mulDivDown(10**data.cellarDecimals, totalSupply);

        if (data.exactHighWatermark > 0) {
            // Calculate Management Fees owed.
            uint256 elapsedTime = block.timestamp - data.timestamp;
            if (elapsedTime > 0) {
                input.feeEarned += input
                    .totalAssets
                    .min(data.totalAssets)
                    .mulDivDown(data.managementFee, 10**BPS_DECIMALS)
                    .mulDivDown(elapsedTime, 365 days);
            }

            // Calculate Performance Fees owed.
            if (input.exactSharePrice > data.exactHighWatermark) {
                input.feeEarned += input
                    .totalAssets
                    .min(data.totalAssets)
                    .mulDivDown(input.exactSharePrice - data.exactHighWatermark, PRECISION_MULTIPLIER)
                    .mulDivDown(data.performanceFee, 10**BPS_DECIMALS);
            }
        } // else Cellar needs to finish its setup..
        // This will trigger `performUpkeep` to save the totalAssets, exactHighWatermark, and timestamp.

        // Setup cellar in input, so that performUpkeep can still run update pending values.
        input.cellar = cellar;
    }
}
