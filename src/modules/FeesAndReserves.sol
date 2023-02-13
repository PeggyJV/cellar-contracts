// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Registry, Owned, ERC20, SafeTransferLib, Math, Address, IGravity } from "src/base/Cellar.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { console } from "@forge-std/Test.sol";

// TODO how do we reset HWM? Could have the owner do it, or maybe we could allow the strategist to do it, but rate limit it to a monthly reset?
// TODO we could allow strategists to reset it, but once reset it can't be reset for a month?
// TODO add method to shutdown this contract and only allow withdraws
contract FeesAndReserves is Owned, AutomationCompatibleInterface {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    uint8 public constant BPS_DECIMALS = 4;
    uint8 public constant HWM_DECIMALS = 18;
    uint256 public constant SECONDS_IN_A_YEAR = 365 days;
    uint256 public constant MAX_PERFORMANCE_FEE = 3 * 10**(BPS_DECIMALS - 1); // 30%

    struct MetaData {
        ERC20 reserveAsset; // Same as cellars accounting asset
        uint32 targetAPR; // The annual APR the cellar targets
        uint64 timestamp; // Timestamp fees were last logged
        uint256 reserves; // Total amount of `reserveAsset` cellar has in reserves
        uint256 highWaterMark; // The Cellars Share Price High Water Mark with 18 decimals
        uint256 totalAssets; // The Cellars totalAssets with 18 decimals
        uint256 performanceFeesOwed; // The performance fees cellar has earned, to be paid out
        uint8 cellarDecimals;
        uint8 reserveAssetDecimals;
        uint32 performanceFee;
    }

    struct PendingMetaData {
        uint32 pendingTargetAPR;
        uint32 pendingPerformanceFee;
    }

    struct PerformInput {
        Cellar cellar;
        uint256 feeEarned;
        uint256 sharePrice;
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

    //============================== Strategist Functions(called through adaptors) ===============================
    // NOTE these function are callable by anyone, but they all use msg.sender determine what cellar they are affecting.

    // Strategist function
    function setupMetaData(uint32 targetAPR, uint32 performanceFee) external {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) != address(0)) revert("Cellar already setup.");
        if (performanceFee > MAX_PERFORMANCE_FEE) revert("Large Fee.");
        ERC20 reserveAsset = cellar.asset();
        uint8 cellarDecimals = cellar.decimals();
        uint8 reserveAssetDecimals = reserveAsset.decimals();

        metaData[cellar] = MetaData({
            reserveAsset: reserveAsset,
            targetAPR: targetAPR,
            timestamp: uint64(block.timestamp),
            reserves: 0,
            highWaterMark: 0,
            totalAssets: 0,
            performanceFeesOwed: 0,
            cellarDecimals: cellarDecimals,
            reserveAssetDecimals: reserveAssetDecimals,
            performanceFee: performanceFee
        });

        // Update pending values to match actual.
        pendingMetaData[cellar].pendingTargetAPR = targetAPR;
        pendingMetaData[cellar].pendingPerformanceFee = performanceFee;
    }

    /**
     * @notice Strategist callable, value is immediately used.
     */
    function changeUpkeepFrequency(uint64 newFrequency) external {
        Cellar cellar = Cellar(msg.sender);
        cellarToUpkeepData[cellar].frequency = newFrequency;
    }

    /**
     * @notice Strategist callable, value is immediatley used.
     */
    function changeUpkeepMaxGas(uint64 newMaxGas) external {
        Cellar cellar = Cellar(msg.sender);
        cellarToUpkeepData[cellar].maxGas = newMaxGas;
    }

    /**
     * @notice Strategist callable, value is only used after
     *         performUpkeep is ran for the cellar.
     */
    function updatePerformanceFee(uint32 performanceFee) external {
        Cellar cellar = Cellar(msg.sender);
        PendingMetaData storage data = pendingMetaData[cellar];

        data.pendingPerformanceFee = performanceFee;

        // TODO emit an event.
    }

    /**
     * @notice Strategist callable, value is only used after
     *         performUpkeep is ran for the cellar.
     */
    function updateTargetAPR(uint32 targetAPR) external {
        Cellar cellar = Cellar(msg.sender);

        PendingMetaData storage data = pendingMetaData[cellar];

        data.pendingTargetAPR = targetAPR;

        // TODO emit an event.
    }

    /**
     * @notice Allows strategists to freely move assets into reserves.
     */
    function addAssetsToReserves(uint256 amount) external {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");
        MetaData storage data = metaData[cellar];

        data.reserves += amount;
        data.reserveAsset.safeTransferFrom(msg.sender, address(this), amount);

        // TODO emit an event.
    }

    /**
     * @notice Allows strategists to freely move assets from reserves.
     */
    function withdrawAssetsFromReserves(uint256 amount) external {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");
        MetaData storage data = metaData[cellar];

        data.reserves -= amount;
        data.reserveAsset.safeTransfer(msg.sender, amount);
        // TODO emit an event
    }

    /**
     * @dev removes assets from reserves, so that `sendFees` can be called.
     * @param amount the amount of reserves to set aside for fees.
     */
    function prepareFees(uint256 amount) external {
        Cellar cellar = Cellar(msg.sender);
        MetaData storage data = metaData[cellar];

        if (address(data.reserveAsset) == address(0)) revert("Cellar not setup.");

        if (amount > data.performanceFeesOwed) revert("Not enough fees owed.");
        if (amount > data.reserves) revert("Not enough reserves.");

        // Reduce fees owed and reduce reserves.
        data.performanceFeesOwed -= amount;
        data.reserves -= amount;

        feesReadyForClaim[cellar] += amount;
    }

    //============================== Public Functions(called by anyone) ===============================

    function sendFees(Cellar cellar) public {
        MetaData storage data = metaData[cellar];

        if (address(data.reserveAsset) == address(0)) revert("Cellar not setup.");
        uint256 payout = feesReadyForClaim[cellar];
        if (payout == 0) revert("Nothing to payout.");

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
    }

    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData) {
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
            if (input.feeEarned > 0 || metaData[cellars[i]].highWaterMark == 0) {
                upkeepNeeded = true;
                performInput[i] = input;
            }
        }

        if (upkeepNeeded) performData = abi.encode(performInput);
    }

    function performUpkeep(bytes calldata performData) external {
        PerformInput[] memory performInput = abi.decode(performData, (PerformInput[]));
        if (msg.sender != automationRegistry) {
            // Do not trust callers perform input data.
            for (uint256 i; i < performInput.length; ++i) {
                Cellar target = performInput[i].cellar;
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
                    data.performanceFeesOwed += performInput[i].feeEarned;
                    data.highWaterMark = performInput[i].sharePrice;
                    data.timestamp = performInput[i].timestamp;
                    data.totalAssets = performInput[i].totalAssets;
                    upkeepData.lastUpkeepTime = uint64(block.timestamp);
                } else if (data.highWaterMark == 0) {
                    // Need to set up cellar by setting HWM, TA, and timestamp.
                    data.highWaterMark = performInput[i].sharePrice;
                    data.timestamp = performInput[i].timestamp;
                    data.totalAssets = performInput[i].totalAssets;
                    upkeepData.lastUpkeepTime = uint64(block.timestamp);
                }
            }
            // If there are fees ready for claiming, call sendFees.
            if (feesReadyForClaim[performInput[i].cellar] > 0) {
                sendFees(performInput[i].cellar);
            }

            // Update pending values if need be.
            PendingMetaData storage pending = pendingMetaData[performInput[i].cellar];
            if (data.targetAPR != pending.pendingTargetAPR) data.targetAPR = pending.pendingTargetAPR;
            if (data.performanceFee != pending.pendingPerformanceFee)
                data.performanceFee = pending.pendingPerformanceFee;
        }
    }

    // TODO seems to have very bad precision...
    function _calculateFees(Cellar cellar) internal view returns (PerformInput memory input) {
        MetaData memory data = metaData[cellar];

        uint256 totalAssets = cellar.totalAssets();

        // Convert Assets to HWM decimals.
        totalAssets = totalAssets.changeDecimals(data.reserveAssetDecimals, HWM_DECIMALS);

        {
            uint256 totalSupply = cellar.totalSupply();
            // Share price with HWM decimals.
            input.sharePrice = totalAssets.mulDivDown(10**data.cellarDecimals, totalSupply);
        }

        if (data.highWaterMark == 0) {
            // Cellar has not been set up, so no need to calcualte fees earned.
            input.cellar = cellar;
            input.timestamp = uint64(block.timestamp);
            input.totalAssets = totalAssets;
        } else if (input.sharePrice > data.highWaterMark) {
            // calculate Actual APR.
            uint256 actualAPR;

            {
                uint256 percentIncrease = input.sharePrice.mulDivDown(10**HWM_DECIMALS, data.highWaterMark) -
                    10**HWM_DECIMALS;
                console.log("Percent Increase", percentIncrease);
                actualAPR = percentIncrease.mulDivDown(SECONDS_IN_A_YEAR, uint64(block.timestamp) - data.timestamp);
                console.log("Actual APR", actualAPR);
            }
            // Convert 4 decimal values to 18 decimals for increased precision.
            uint256 targetAPR = uint256(data.targetAPR).changeDecimals(BPS_DECIMALS, HWM_DECIMALS);
            uint256 performanceFee = uint256(data.performanceFee).changeDecimals(BPS_DECIMALS, HWM_DECIMALS);
            if (actualAPR >= targetAPR) {
                // Performance fee is based off target apr.
                input.feeEarned = totalAssets.min(data.totalAssets).mulDivDown(targetAPR, 10**HWM_DECIMALS).mulDivDown(
                    performanceFee,
                    10**HWM_DECIMALS
                );
            } else {
                // Performance fee is based off how close cellar got to target apr.
                uint256 feeMultiplier = 10**HWM_DECIMALS -
                    (targetAPR - actualAPR).mulDivDown(10**HWM_DECIMALS, targetAPR);
                console.log("Fee Multipler", feeMultiplier);
                input.feeEarned = totalAssets
                    .min(data.totalAssets)
                    .mulDivDown(actualAPR, 10**HWM_DECIMALS)
                    .mulDivDown(performanceFee, 10**HWM_DECIMALS)
                    .mulDivDown(feeMultiplier, 10**HWM_DECIMALS);
            }
            // Convert Fees earned from a yearly value to one based off time since last fee log.
            input.feeEarned = input.feeEarned.mulDivDown(uint64(block.timestamp) - data.timestamp, SECONDS_IN_A_YEAR);

            // Now that all the math is done, convert fee earned back into reserve decimals.
            input.feeEarned = input.feeEarned.changeDecimals(HWM_DECIMALS, data.reserveAssetDecimals);

            input.cellar = cellar;
            input.timestamp = uint64(block.timestamp);
            input.totalAssets = totalAssets;
        } // else No performance fees are rewarded.
    }

    function getActualAPR(Cellar cellar) external view returns (uint32 actualAPR) {
        MetaData memory data = metaData[cellar];
        if (address(data.reserveAsset) == address(0)) revert("Cellar not setup.");

        uint256 totalAssets = cellar.totalAssets();

        // Convert Assets to HWM decimals.
        totalAssets = totalAssets.changeDecimals(data.reserveAssetDecimals, HWM_DECIMALS);

        uint256 sharePrice;
        {
            uint256 totalSupply = cellar.totalSupply();
            // Share price with HWM decimals.
            sharePrice = totalAssets.mulDivDown(10**data.cellarDecimals, totalSupply);
        }
        if (sharePrice > data.highWaterMark) {
            // calculate Actual APR.

            uint256 percentIncrease = sharePrice.mulDivDown(10**BPS_DECIMALS, data.highWaterMark);
            actualAPR = uint32(percentIncrease.mulDivDown(SECONDS_IN_A_YEAR, uint64(block.timestamp) - data.timestamp));
        } // else actual apr is zero bc share price is still below hwm.
    }
}
