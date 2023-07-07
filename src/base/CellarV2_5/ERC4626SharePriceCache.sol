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
            if (timeDelta >= minimumTimeDelta) {
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
        ans = answer;
        (timeWeightedAverageAnswer, timeUpdated) = _getTimeWeightedAverageAnswerAndTimeUpdated();
    }

    function _getTargetSharePrice() internal view returns (uint256 sharePrice) {
        uint256 totalShares = target.totalSupply();
        uint256 totalAssets = target.totalAssets();

        sharePrice = totalShares == 0
            ? ONE_SHARE.changeDecimals(18, decimals)
            : ONE_SHARE.mulDivDown(totalAssets, totalShares);
    }

    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        // Get target share price.
        uint256 sharePrice = _getTargetSharePrice();
        uint256 currentAnswer = answer;

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
        if (timeDeltaSincePreviousCumulative > cumulativeUpdateDuration) {
            currentIndex = currentCumulative.next;
            // Update newest cumulative.
            CumulativeData storage newCumulative = cumulativeData[currentIndex];
            newCumulative.cumulative = currentCumulative.cumulative;
            newCumulative.timestamp = currentTime;
        }
    }
}
