// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, SafeTransferLib, Math, ERC20 } from "src/base/ERC4626.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IGravity } from "src/interfaces/external/IGravity.sol";
import { Uint32Array } from "src/utils/Uint32Array.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { Owned } from "@solmate/auth/Owned.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

import { console } from "@forge-std/Test.sol";

// TODO this could implement the chainlink data feed interface!
contract ERC4626SharePriceOracle is AutomationCompatibleInterface {
    using Math for uint256;
    // Determines when answer is stale, and also the minimum time each observation must last.
    uint64 public immutable heartbeat;
    // Determines how far off observations used in a TWAA calculation can be from the heartbeat.
    // IE if 4 observations are used, then the delta time between those 4 observations must be within
    // 3*heartbeat -> 3*heartbeat+gracePeriod.
    uint64 public immutable gracePeriod;
    // minimum value is 1 bps
    // max is 10,000 bps
    // Note for daily updates, a 1 bps deviation trigger would update about every day if the ERC4626 APR is 3.7%
    // this value should really be refelctive of the cellars expected maximum APR/ maximum interest earned during a heartbeat duration.
    uint64 public immutable deviationTrigger;
    uint256 public immutable ONE_SHARE;
    uint8 public immutable decimals;
    uint8 public constant SCALING_DECIMALS = 18;

    // ERC4626 Target to save pricing information for.
    ERC4626 public immutable target;

    uint256 public answer;

    struct Observation {
        uint64 timestamp;
        uint192 cumulative;
    }

    Observation[] public observations;

    uint256 public currentIndex;

    /**
     * @dev _observationsToUse * _heartbeat = TWAA duration possibly(+ gracePeriod)
     * @dev TWAA duration at a minimum will be _observationsToUse * _heartbeat.
     * @dev TWAA duration at a maximum will be _observationsToUse * _heartbeat + _gracePeriod.
     * @dev NOTE TWAA calcs will use the most recently completed observation, which can at most be ~heartbeat stale
     */
    constructor(
        ERC4626 _target,
        uint64 _heartbeat,
        uint64 _deviationTrigger,
        uint64 _gracePeriod,
        uint256 _observationsToUse
    ) {
        target = _target;
        decimals = target.decimals();
        ONE_SHARE = 10 ** decimals;
        heartbeat = _heartbeat;
        deviationTrigger = _deviationTrigger;
        gracePeriod = _gracePeriod;
        uint256 observationsLength = _observationsToUse + 1;

        // Grow Observations array to required length, and fill it with observations that use 1 for timestamp and cumulative.
        // That way the initial upkeeps won't need to change state from 0 which is more expensive.
        for (uint256 i; i < observationsLength; ++i) observations.push(Observation({ timestamp: 1, cumulative: 1 }));
    }

    function _getNextIndex(uint256 _currentIndex, uint256 _length) internal pure returns (uint256 nextIndex) {
        nextIndex = (_currentIndex == _length - 1) ? 0 : _currentIndex + 1;
    }

    function _getPreviousIndex(uint256 _currentIndex, uint256 _length) internal pure returns (uint256 previousIndex) {
        previousIndex = (_currentIndex == 0) ? _length - 1 : _currentIndex - 1;
    }

    function _getTimeWeightedAverageAnswer()
        internal
        view
        returns (uint256 timeWeightedAverageAnswer, bool notSafeToUse)
    {
        uint256 _currentIndex = currentIndex;
        uint256 _length = observations.length;
        Observation memory mostRecentlyCompletedObservation = observations[_getPreviousIndex(_currentIndex, _length)];
        Observation memory oldestObservation = observations[_getNextIndex(_currentIndex, _length)];
        // Data is not set.
        if (oldestObservation.timestamp == 1) return (0, true);

        uint256 timeDelta = mostRecentlyCompletedObservation.timestamp - oldestObservation.timestamp;
        /// @dev use _length - 2 because
        /// remove 1 because observations array stores the current pending observation.
        /// remove 1 because we are really interested in the time between observations.
        uint256 minDuration = heartbeat * (_length - 2);
        uint256 maxDuration = minDuration + gracePeriod;
        // Data is too new
        // TODO we should realisitcally never hit this if we confirm observations always last a minimum of heartbeat.
        if (timeDelta < minDuration) return (0, true);
        // Data is too old
        if (timeDelta > maxDuration) return (0, true);

        timeWeightedAverageAnswer =
            (mostRecentlyCompletedObservation.cumulative - oldestObservation.cumulative) /
            (mostRecentlyCompletedObservation.timestamp - oldestObservation.timestamp);
    }

    // TODO we might be able to get away with packing all these values into a single struct
    struct ProposedReturnStructForGetLatest {
        uint120 answer;
        uint120 timeWeightedAverageAnswer;
        bool notSafeToUse;
    }

    function getLatest() external view returns (uint256 ans, uint256 timeWeightedAverageAnswer, bool notSafeToUse) {
        // Check if upkeep is underfunded, if so set notSafeToUse to true, and return.

        // Check if answer is stale, if so set notSafeToUse to true, and return.
        uint256 timeDeltaSinceLastUpdated = block.timestamp - observations[currentIndex].timestamp;
        // Note add in the grace period here, because it can take time for the upkeep TX to go through.
        if (timeDeltaSinceLastUpdated > (heartbeat + gracePeriod)) return (0, 0, true);

        ans = answer;
        // Scale results back down to cellar asset decimals.
        ans = ans.changeDecimals(SCALING_DECIMALS, decimals);

        (timeWeightedAverageAnswer, notSafeToUse) = _getTimeWeightedAverageAnswer();
        if (notSafeToUse) return (0, 0, true);
        timeWeightedAverageAnswer = timeWeightedAverageAnswer.changeDecimals(SCALING_DECIMALS, decimals);
    }

    function _getTargetSharePrice() internal view returns (uint256 sharePrice) {
        uint256 totalShares = target.totalSupply();
        // Get total Assets but scale it up to 18 decimals of precision.
        // TODO is this scaling needed?
        uint256 totalAssets = target.totalAssets().changeDecimals(decimals, SCALING_DECIMALS);

        if (totalShares == 0) return 0;

        sharePrice = ONE_SHARE.mulDivDown(totalAssets, totalShares);
    }

    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        // Get target share price.
        uint256 sharePrice = _getTargetSharePrice();
        uint256 currentAnswer = answer;

        // See if we need to update because answer is stale or outside deviation.
        uint256 _currentIndex = currentIndex;
        // Time since answer was last updated.
        uint256 timeDeltaCurrentAnswer = block.timestamp - observations[_currentIndex].timestamp;
        uint256 timeDeltaSincePreviousObservation = block.timestamp -
            observations[_getPreviousIndex(_currentIndex, observations.length)].timestamp;
        uint64 _heartbeat = heartbeat;
        if (
            timeDeltaCurrentAnswer >= _heartbeat ||
            timeDeltaSincePreviousObservation >= _heartbeat ||
            sharePrice > currentAnswer.mulDivDown(1e4 + deviationTrigger, 1e4) ||
            sharePrice < currentAnswer.mulDivDown(1e4 - deviationTrigger, 1e4)
        ) {
            // We need to update answer.
            upkeepNeeded = true;
            performData = abi.encode(sharePrice, uint64(block.timestamp));
        }
    }

    function performUpkeep(bytes calldata performData) external {
        // TODO msg.sender should be registry
        (uint256 sharePrice, uint64 currentTime) = abi.decode(performData, (uint256, uint64));

        // Update answer.
        answer = sharePrice;

        // Update current observation.
        uint256 _currentIndex = currentIndex;
        uint256 _length = observations.length;
        Observation storage currentObservation = observations[_currentIndex];
        // Make sure time is larger than previous time.
        if (currentObservation.timestamp >= currentTime) revert("Bad time given");

        uint256 timeDelta = currentTime - currentObservation.timestamp;
        uint256 currentCumulative = currentObservation.cumulative + (sharePrice * timeDelta);
        // TODO this check realistically is not needed, but can talk with auditors about it.
        if (currentCumulative > type(uint192).max) revert("Cumulative Too large");
        currentObservation.cumulative = uint192(currentCumulative);
        currentObservation.timestamp = currentTime;

        uint256 timeDeltaSincePreviousObservation = currentTime -
            observations[_getPreviousIndex(_currentIndex, _length)].timestamp;
        // See if we need to advance to the next cumulative.
        if (timeDeltaSincePreviousObservation >= heartbeat) {
            uint256 nextIndex = _getNextIndex(_currentIndex, _length);
            currentIndex = nextIndex;
            // Update newest cumulative.
            Observation storage newObservation = observations[nextIndex];
            newObservation.cumulative = uint192(currentCumulative);
            newObservation.timestamp = currentTime;
        }
    }
}
