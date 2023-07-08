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
    uint64 public immutable deviationTrigger;
    uint256 public immutable ONE_SHARE;
    uint8 public immutable decimals;

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

    function _getTimeWeightedAverageAnswer() internal view returns (uint256 twaa) {
        uint256 _currentIndex = currentIndex;
        uint256 _length = observations.length;
        Observation memory mostRecentlyCompletedObservation = observations[_getPreviousIndex(_currentIndex, _length)];
        Observation memory oldestObservation = observations[_getNextIndex(_currentIndex, _length)];
        if (oldestObservation.timestamp == 1) revert("CumulativeData not set");

        uint256 timeDelta = mostRecentlyCompletedObservation.timestamp - oldestObservation.timestamp;
        /// @dev use _length - 2 because
        /// remove 1 because observations array stores the current pending observation.
        /// remove 1 because we are really interested in the time between observations.
        uint256 minDuration = heartbeat * (_length - 2);
        uint256 maxDuration = minDuration + gracePeriod;
        if (timeDelta < minDuration) revert("CumulativeData too new");
        if (timeDelta > maxDuration) revert("CumulativeData too old");

        twaa =
            (mostRecentlyCompletedObservation.cumulative - oldestObservation.cumulative) /
            (mostRecentlyCompletedObservation.timestamp - oldestObservation.timestamp);
    }

    function getLatest() external view returns (uint256 ans, uint256 timeWeightedAverageAnswer, uint256 timeUpdated) {
        // TODO could revert if upkeep is underfunded
        // TODO could revert if answer is stale.
        // TODO ORRRRR this can return a bool indicaitng their was a problem, and that the values can not be used.
        // TODO for staleness check, we could do heartbeat + gracePeriod
        // Also if we do the check here we dont need to return the timeUpdated.
        ans = answer;
        timeWeightedAverageAnswer = _getTimeWeightedAverageAnswer();
        timeUpdated = observations[currentIndex].timestamp;
        // TODO is this scaling needed?
        // Scale results back down to cellar asset decimals.
        ans = ans.changeDecimals(18, decimals);
        timeWeightedAverageAnswer = timeWeightedAverageAnswer.changeDecimals(18, decimals);
    }

    function _getTargetSharePrice() internal view returns (uint256 sharePrice) {
        uint256 totalShares = target.totalSupply();
        // Get total Assets but scale it up to 18 decimals of precision.
        // TODO is this scaling needed?
        uint256 totalAssets = target.totalAssets().changeDecimals(decimals, 18);

        if (totalShares == 0) return 0;

        sharePrice = ONE_SHARE.mulDivDown(totalAssets, totalShares);
    }

    // TODO maybe maximum time delta should be the minimum time delta plus (cumulativeUpdateDuration - 1) + timeTrigger
    // Ideally if we miss a normal upkeep, this should start reverting from cumulative data that is too old.
    // TODO so the wanted behavior is we want a small buffer around when the normal upkeep should happen since it is unliely to happen right at 1 days
    // If we do miss an upkeep, then pricing should start reverting from staleness, and even when the answer is updated, the TWASP answer should revert from being too old.

    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        // Get target share price.
        uint256 sharePrice = _getTargetSharePrice();
        uint256 currentAnswer = answer;
        // TODO so we could have this check if the timeDelta between now and the previous cumulative is greater than the cumulativeUpdateDuration, and if so, call performUpkeep.
        // Otherwise there is an edgecase where answer is updated from deviation, and the time it is updated is 1 second short of the time delta between previous and now IE
        // if update duration is 1 day, and the answer is updated 1 second before the updateDuration would advance the index, then the next update could take a full day
        // to go through, so now the current cumulative data is now holding data for 2 days - 1 second, instead of holding data for roughly 1 day(the update duration)
        // TODO the max possible cumulative data duration is = (cumulativeUpdateDuration - 1) + timeTrigger;
        // So minimumTimeDelta should be no smaller than cumulativeUpdateDuration + timeTrigger
        // And no larger than (cumulativeUpdateDuration * (cumulativeLength-1))
        // Then maximumTimeDelta should be no smaller than (2*cumulativeUpdateDuration - 1) + timeTrigger cuz that is the smalleset possible cumulative data can be
        // And maximumTimeDelta should be no larger than (cumulativeUpdateDuration * cumulativeLength)
        // And we always know that the previous cumulative timestamp is the timestamp of when the current cumulative started

        // TODO the heartbeat value should be significantly less than the minimumTimeDelta, otherwise you don't get any TWAP action.
        // If minimumTimeDelta ~ heartbeat then the latest cumulative answer is weighted for the same length as the minimum twap duration.
        // TODO so myabe for saftey the constructor should enforce heartbeat is 1/2 or 1/3 of the minimumTimeDelta?

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
        uint256 timeDelta = currentTime - currentObservation.timestamp;
        uint256 currentCumulative = currentObservation.cumulative + (sharePrice * timeDelta);
        if (currentCumulative > type(uint192).max) revert("Cumulative Too large");
        currentObservation.cumulative = uint192(currentCumulative);
        // Make sure time is larger than previous time.
        if (currentObservation.timestamp >= currentTime) revert("Bad time given");
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
