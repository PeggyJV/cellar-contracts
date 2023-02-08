// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Registry, Owned, ERC20, SafeTransferLib, Math, Address, IGravity } from "src/base/Cellar.sol";

contract FeesAndReserves is Owned {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    uint256 public constant BPS_DECIMALS = 4;
    uint8 public constant HWM_DECIMALS = 18;
    uint256 public constant SECONDS_IN_A_YEAR = 86400 * 365;
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

    mapping(Cellar => MetaData) public metaData;

    mapping(Cellar => uint256) public feesReadyForClaim;

    constructor() Owned(msg.sender) {}

    // TODO so this reverts cuz we do a re-entrancy... So could we have a chainlink upkeep ocassionally log these values? Maybe weekly?
    // maybe the strategist just moves assets into reserves, then the upkeep will log fees and prepare fees?
    // If we did do keepers, could our upkeep take some assets from reserves and covnert them to link to top up the upkeep?

    // Strategist function
    function setupMetaData(uint32 targetAPR, uint32 performanceFee) external {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) != address(0)) revert("Cellar already setup.");
        if (performanceFee > MAX_PERFORMANCE_FEE) revert("Large Fee.");
        ERC20 reserveAsset = cellar.asset();
        uint256 totalAssets = cellar.totalAssets();
        uint256 totalSupply = cellar.totalSupply();
        if (totalSupply == 0) revert("No supply");
        uint8 cellarDecimals = cellar.decimals();
        uint8 reserveAssetDecimals = reserveAsset.decimals();

        // Convert Assets to HWM decimals.
        totalAssets = totalAssets.changeDecimals(reserveAssetDecimals, HWM_DECIMALS);

        // Share price with HWM decimals.
        uint256 sharePrice = totalAssets.mulDivDown(10**cellarDecimals, totalSupply);

        metaData[cellar] = MetaData({
            reserveAsset: reserveAsset,
            targetAPR: targetAPR,
            timestamp: uint64(block.timestamp),
            reserves: 0,
            highWaterMark: sharePrice,
            totalAssets: totalAssets,
            performanceFeesOwed: 0,
            cellarDecimals: cellarDecimals,
            reserveAssetDecimals: reserveAssetDecimals,
            performanceFee: performanceFee
        });
    }

    // TODO how do we reset HWM? Could have the owner do it, or maybe we could allow the strategist to do it, but rate limit it to a monthly reset?
    // TODO we could allow strategists to reset it, but once reset it can't be reset for a month?
    // Strategist function
    function updatePerformanceFee(uint32 performanceFee) external {
        Cellar cellar = Cellar(msg.sender);
        MetaData storage data = metaData[cellar];
        _logFees(cellar, data);

        data.performanceFee = performanceFee;

        // TODO emit an event.
    }

    // Strategist function
    function updateTargetAPR(uint32 targetAPR) external {
        Cellar cellar = Cellar(msg.sender);

        MetaData storage data = metaData[cellar];
        _logFees(cellar, data);

        data.targetAPR = targetAPR;

        // TODO emit an event.
    }

    // Strategist function
    function addAssetsToReserves(uint256 amount) external {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");
        MetaData storage data = metaData[cellar];

        data.reserveAsset.safeTransferFrom(msg.sender, address(this), amount);

        // TODO emit an event.
    }

    // Strategist function
    function withdrawAssetsFromReserves(uint256 amount) external {
        Cellar cellar = Cellar(msg.sender);
        if (address(metaData[cellar].reserveAsset) == address(0)) revert("Cellar not setup.");
        MetaData storage data = metaData[cellar];

        data.reserves -= amount;
        data.reserveAsset.safeTransfer(msg.sender, amount);
        // TODO emit an event
    }

    // TODO what would happen if we allow strategists to build up performance fees? Like
    // maybe we dont punsih them by zeroing out performacne fees owed, if reserves can't cover it?
    // would strategists be able to build up a bunch of fees owed and drain assets out of the cellar?
    // I guess they could do move assets into reserves if the TVL doesn't trip the total assets check....
    // Strategist function
    /**
     * @dev removes assets from reserves, so that `sendFees` can be called.
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

    function logFees() external {
        Cellar cellar = Cellar(msg.sender);
        _logFees(cellar, metaData[cellar]);
    }

    // Callable by anyone
    function sendFees(Cellar cellar) external {
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

    function _logFees(Cellar cellar, MetaData storage data) internal {
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
            uint256 annualAPR;

            {
                uint256 percentIncrease = sharePrice.mulDivDown(10**BPS_DECIMALS, data.highWaterMark);
                annualAPR = percentIncrease.mulDivDown(SECONDS_IN_A_YEAR, uint64(block.timestamp) - data.timestamp);
            }
            uint256 feeEarned;
            if (annualAPR >= data.targetAPR) {
                // Performance fee is based off target apr.
                feeEarned = totalAssets.min(data.totalAssets).mulDivDown(data.targetAPR, 10**BPS_DECIMALS).mulDivDown(
                    data.performanceFee,
                    10**BPS_DECIMALS
                );
            } else {
                // Performance fee is based off how close cellar got to target apr
                uint256 feeMultiplier = (data.targetAPR - annualAPR).mulDivDown(10**BPS_DECIMALS, data.targetAPR);
                feeEarned = totalAssets
                    .min(data.totalAssets)
                    .mulDivDown(annualAPR, 10**BPS_DECIMALS)
                    .mulDivDown(data.performanceFee, 10**BPS_DECIMALS)
                    .mulDivDown(feeMultiplier, 10**BPS_DECIMALS);
            }
            // Convert Fees earned from a yearly value to one based off time since last fee log.
            feeEarned = feeEarned.mulDivDown(uint64(block.timestamp) - data.timestamp, SECONDS_IN_A_YEAR);
            // Save the earned fees.
            data.performanceFeesOwed += feeEarned;

            // Update the High watermark.
            data.highWaterMark = sharePrice;
        } // else No performance fees are rewarded..

        // Update meta data
        data.timestamp = uint64(block.timestamp);
        data.totalAssets = totalAssets;
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
