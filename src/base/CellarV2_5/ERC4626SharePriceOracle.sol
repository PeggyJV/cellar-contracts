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
    bool public immutable revertOnBadAnswer;
    // The delta time between the currentCumulativeData timestamp, and the previous cumulativeData timestamp, that causes currentIndex to advance.
    uint64 public immutable cumulativeUpdateDuration;
    // The minimum amount of time between to cumulatives that can be used to get a TWAP.
    uint64 public immutable minimumTimeDelta;
    // The maximum amount of time between to cumulatives that can be used to get a TWAP.
    uint64 public immutable maximumTimeDelta;
    uint8 public immutable cumulativeLength;
    // The deviation in current answer, and last answer that triggers an upkeep.
    uint64 public immutable deviationTrigger;
    // The amount of time that passes between updates that triggers an upkeep.
    uint64 public immutable timeTrigger;
    uint256 public immutable ONE_SHARE;
    uint8 public immutable decimals;

    // ERC4626 Target to save pricing information for.
    ERC4626 public immutable target;

    uint256 public answer;

    struct CumulativeData {
        uint8 next;
        uint8 previous;
        uint64 timestamp;
        uint176 cumulative;
    }

    mapping(uint256 => CumulativeData) public cumulativeData;
    uint8 public currentIndex;

    constructor(
        ERC4626 _target,
        uint64 _timeTrigger,
        uint64 _deviationTrigger,
        uint64 _minimumTimeDelta,
        uint64 _maximumTimeDelta,
        bool _revertOnBadAnswer,
        uint64 _cumulativeUpdateDuration,
        uint8 _cumulativeLength
    ) {
        target = _target;
        decimals = target.decimals();
        ONE_SHARE = 10 ** decimals;
        timeTrigger = _timeTrigger;
        deviationTrigger = _deviationTrigger;
        minimumTimeDelta = _minimumTimeDelta;
        maximumTimeDelta = _maximumTimeDelta;
        revertOnBadAnswer = _revertOnBadAnswer;
        cumulativeUpdateDuration = _cumulativeUpdateDuration;
        cumulativeLength = _cumulativeLength;
        uint8 minCumulativeIndex = 0;
        uint8 maxCumulativeIndex = _cumulativeLength - 1;
        for (uint256 i; i < _cumulativeLength; ++i) {
            if (i == maxCumulativeIndex) cumulativeData[i].next = minCumulativeIndex;
            else cumulativeData[i].next = uint8(i + 1);
            if (i == minCumulativeIndex) cumulativeData[i].previous = maxCumulativeIndex;
            else cumulativeData[i].previous = uint8(i - 1);
        }
    }

    // TODO this should enforce that we are using atleast 3 cumulative data entries,
    // Cuz if you just go to the previous one, then the share price you are using could possibly be whatever the share price was in the previoud cumulative data
    // which could have just been updated by time
    function _getTimeWeightedAverageAnswerAndTimeUpdated() internal view returns (uint256 twaa, uint64 timeUpdated) {
        // Get the newest cumulative.
        CumulativeData memory newData = cumulativeData[currentIndex];
        // Now find a cumulative that is far eno[ugh in the past that minimumTimeDelta is met, but fresh enough that maximumTimeDelta is met.
        // Max possible iterations is the cumulative length - 1, since we start checking the previous cumulative.
        CumulativeData memory oldData = cumulativeData[newData.previous];
        for (uint256 i; i < cumulativeLength - 1; ++i) {
            if (oldData.timestamp == 0) revert("CumulativeData not set");
            uint256 timeDelta = newData.timestamp - oldData.timestamp;
            // Check if Previous is good.
            // Also make sure we have gone sufficiently far back so that we are atleast using 3 cumulative datas to
            // calculate TWAA.
            // Why 3? The first one can be impartial, if currentIndex is advanced now, then 1 second later deviation triggers another update,
            // the first cumulativeData is only weighted by 1 second, so we are relying mainly on the second cumulative data.
            // We want more than 2 because of the above scenario

            // You need atleast 2 to calcualte a TWAA, because of this setup, if an upkeep happens and updates the current index, then
            // one second later, a deviation triggers an upkeep, the first cumulativeData will only have 1 second of weight, so our TWAA will essentially be
            // whatever the share price was for the immediate previous cumulative data, which might be safe, but if the upkeep is not funded during that time,
            // then that data could just be composed of one data point and is possibly unsafe to use, so we use 3, so that we know we atleast have 2 safe data points.
            // TODO this 2 could probs be an input, and I think every number you add to it would mean the delta between the min and max time delta should increase
            // by 1 heartbeat. Then in my test I need to add another performUpkeep on line 208
            if (i >= 2 && timeDelta >= minimumTimeDelta) {
                // Previous is old enough, make sure it is fresh enough.
                if (timeDelta <= maximumTimeDelta) {
                    // Previous is old enough, and fresh enough, so use it.
                    break;
                } else {
                    // We found a previous cumulative that is old enough, but it is too old so there is no point in continuing to look.
                    revert("CumulativeData too old");
                }
            } else {
                // Previous is not usable.
                // Make sure we aren't at the end.
                if (i == cumulativeLength - 1) revert("CumulativeData too new");
                //Go back 1.
                oldData = cumulativeData[oldData.previous];
            }
        }

        // At this point we have a cumulative that will work so calculate the time weighted average answer.
        twaa = (newData.cumulative - oldData.cumulative) / (newData.timestamp - oldData.timestamp);
        timeUpdated = newData.timestamp;
    }

    function getLatest() external view returns (uint256 ans, uint256 timeWeightedAverageAnswer, uint256 timeUpdated) {
        // TODO could revert if upkeep is underfunded
        // TODO could revert if answer is stale.
        ans = answer;
        (timeWeightedAverageAnswer, timeUpdated) = _getTimeWeightedAverageAnswerAndTimeUpdated();
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
        uint256 timeDelta = block.timestamp - cumulativeData[currentIndex].timestamp;
        if (
            timeDelta >= timeTrigger ||
            sharePrice > currentAnswer.mulDivDown(1e4 + deviationTrigger, 1e4) ||
            sharePrice < currentAnswer.mulDivDown(1e4 - deviationTrigger, 1e4)
        ) {
            // We need to update answer.
            upkeepNeeded = true;
            performData = abi.encode(sharePrice, uint64(block.timestamp));
        }
    }

    function performUpkeep(bytes calldata performData) external {
        (uint256 sharePrice, uint64 currentTime) = abi.decode(performData, (uint256, uint64));

        // Update answer.
        answer = sharePrice;

        // Update current cumulative.
        CumulativeData storage currentCumulative = cumulativeData[currentIndex];
        uint256 timeDelta = currentTime - currentCumulative.timestamp;
        currentCumulative.cumulative += uint176(sharePrice * timeDelta);
        currentCumulative.timestamp = currentTime;

        // See if we need to advance to the next cumulative.
        uint256 timeDeltaSincePreviousCumulative = currentTime - cumulativeData[currentCumulative.previous].timestamp;
        if (timeDeltaSincePreviousCumulative >= cumulativeUpdateDuration) {
            currentIndex = currentCumulative.next;
            // Update newest cumulative.
            CumulativeData storage newCumulative = cumulativeData[currentIndex];
            newCumulative.cumulative = currentCumulative.cumulative;
            newCumulative.timestamp = currentTime;
        }
    }
}
