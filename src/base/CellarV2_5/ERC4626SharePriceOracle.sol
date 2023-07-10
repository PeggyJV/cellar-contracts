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

    // ========================================= STRUCTS =========================================

    struct Observation {
        uint64 timestamp;
        uint192 cumulative;
    }

    // TODO we might be able to get away with packing all these values into a single struct
    struct ProposedReturnStructForGetLatest {
        uint120 answer;
        uint120 timeWeightedAverageAnswer;
        bool notSafeToUse;
    }

    // ========================================= GLOBAL STATE =========================================
    /**
     * @notice The latest stored onchain answer.
     */
    uint224 public answer;

    /**
     * @notice Stores the index of observations with the pending Observation.
     */
    uint16 public currentIndex;

    /**
     * @notice The lenght of the observations array.
     * @dev `observations` will never change itsw length once set in the constructor.
     *      By saving this value here, we can take advantage of variable packing to make reads cheaper.
     */
    uint16 public observationsLength;

    /**
     * @notice Stores the observations this contract uses to derive a
     *         time weighted average answer.
     */
    Observation[] public observations;

    uint8 public constant SCALING_DECIMALS = 18;

    //============================== IMMUTABLES ===============================

    // Determines when answer is stale, and also the minimum time each observation must last.
    /**
     * @notice Determines the minimum time for each observation, and is used to determine if an
     *         answer is stale.
     */
    uint64 public immutable heartbeat;

    /**
     * @notice Used to enforce that the summation of each observations delay used in
     *         a time weighed average calculation is less than the gracePeriod.
     * @dev Example: Using a 3 day TWAA with 1 hour grace period.
     *      When calculating the TWAA, the total time must be greater than 3 days but less than
     *      3 days + 1hr. So one observation could be delayed 1 hr, or two observations could be
     *      delayed 30 min each.
     */
    uint64 public immutable gracePeriod;

    /**
     * @notice Number between 0 -> 10_000 that determines how far off the last saved answer
     *         can deviate from the current answer.
     * @dev This value should be reflective of the vaults expected maximum percent share
     *      price change during a heartbeat duration.
     * @dev
     *    -1_000 == 10%
     *    -100 == 1%
     *    -10 == 0.1%
     *    -1 == 0.01% or 1 bps
     */
    uint64 public immutable deviationTrigger;

    /**
     * @notice One share of target vault.
     */
    uint256 public immutable ONE_SHARE;

    /**
     * @notice Target vault decimals.
     */
    uint8 public immutable decimals;

    /**
     * @notice Chainlink's Automation Registry contract address.
     * @notice For mainnet use 0x02777053d6764996e594c3E88AF1D58D5363a2e6.
     */
    address public immutable automationRegistry;

    /**
     * @notice ERC4626 target vault this contract is an oracle for.
     */
    ERC4626 public immutable target;

    // TODO so we could create an upkeep in the constructor, then make it owned by this contract, so that there is no way to cancel the upkeep
    // this does mean if we need to migrate to a new contract the upkeep funds are stuck here, but it makes this oracle setup only reliant
    // on LINK deposits, as opposed to worrying about the owner canceling it.
    // TODO can this emit a low link event? That way if its running low on link it can easily alert us?
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
        uint16 _observationsToUse,
        address _automationRegistry
    ) {
        target = _target;
        decimals = target.decimals();
        ONE_SHARE = 10 ** decimals;
        heartbeat = _heartbeat;
        deviationTrigger = _deviationTrigger;
        gracePeriod = _gracePeriod;
        automationRegistry = _automationRegistry;
        // Add 1 to observations to use.
        _observationsToUse = _observationsToUse + 1;
        observationsLength = _observationsToUse;

        // Grow Observations array to required length, and fill it with observations that use 1 for timestamp and cumulative.
        // That way the initial upkeeps won't need to change state from 0 which is more expensive.
        for (uint256 i; i < _observationsToUse; ++i) observations.push(Observation({ timestamp: 1, cumulative: 1 }));
        // Set to one so slot is dirty for first upkeep.
        answer = 1;
    }

    //============================== CHAINLINK AUTOMATION ===============================

    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        // Get target share price.
        uint224 sharePrice = _getTargetSharePrice();
        // Read state from one slot.
        uint224 _answer = answer;
        uint16 _currentIndex = currentIndex;
        uint16 _observationsLength = observationsLength;

        // See if we need to update because answer is stale or outside deviation.
        // Time since answer was last updated.
        uint256 timeDeltaCurrentAnswer = block.timestamp - observations[_currentIndex].timestamp;
        uint256 timeDeltaSincePreviousObservation = block.timestamp -
            observations[_getPreviousIndex(_currentIndex, _observationsLength)].timestamp;
        uint64 _heartbeat = heartbeat;
        // TODO would we ever have a scenario where performUpkeep is called from
        // `timeDeltaCurrentAnswer >= _heartbeat` being true? Like I think if that is true, then `timeDeltaSincePreviousObservation >= _heartbeat` is also true.
        if (
            timeDeltaCurrentAnswer >= _heartbeat ||
            timeDeltaSincePreviousObservation >= _heartbeat ||
            sharePrice > uint256(_answer).mulDivDown(1e4 + deviationTrigger, 1e4) ||
            sharePrice < uint256(_answer).mulDivDown(1e4 - deviationTrigger, 1e4)
        ) {
            // We need to update answer.
            upkeepNeeded = true;
            performData = abi.encode(sharePrice, uint64(block.timestamp));
        }
    }

    function performUpkeep(bytes calldata performData) external {
        if (msg.sender != automationRegistry) revert("Not automation registry");
        (uint224 sharePrice, uint64 currentTime) = abi.decode(performData, (uint224, uint64));

        // Verify atleast one of the upkeep conditions was met.
        // TODO is this really needed? Like we are already trusting the upkeep to give us a safe
        // share price, and the share price is something we can't really easily verify...
        // TODO this does protect us from 2 upkeep TXs being submitted at the same time by multiple keepers...
        bool upkeepConditionMet;

        // Read state from one slot.
        uint224 _answer = answer;
        uint16 _currentIndex = currentIndex;
        uint16 _observationsLength = observationsLength;

        // See if we are upkeeping because of deviation.
        if (
            sharePrice > uint256(_answer).mulDivDown(1e4 + deviationTrigger, 1e4) ||
            sharePrice < uint256(_answer).mulDivDown(1e4 - deviationTrigger, 1e4)
        ) upkeepConditionMet = true;

        // Update answer.
        answer = sharePrice;

        // Update current observation.
        Observation storage currentObservation = observations[_currentIndex];
        // Make sure time is larger than previous time.
        if (currentObservation.timestamp >= currentTime) revert("Bad time given");

        // See if we are updating because of staleness.
        uint256 timeDelta = currentTime - currentObservation.timestamp;
        if (timeDelta >= heartbeat) upkeepConditionMet = true;

        uint256 currentCumulative = currentObservation.cumulative + (sharePrice * timeDelta);
        // TODO this check realistically is not needed, but can talk with auditors about it.
        if (currentCumulative > type(uint192).max) revert("Cumulative Too large");
        currentObservation.cumulative = uint192(currentCumulative);
        currentObservation.timestamp = currentTime;

        uint256 timeDeltaSincePreviousObservation = currentTime -
            observations[_getPreviousIndex(_currentIndex, _observationsLength)].timestamp;
        // See if we need to advance to the next cumulative.
        if (timeDeltaSincePreviousObservation >= heartbeat) {
            uint16 nextIndex = _getNextIndex(_currentIndex, _observationsLength);
            currentIndex = nextIndex;
            // Update newest cumulative.
            Observation storage newObservation = observations[nextIndex];
            newObservation.cumulative = uint192(currentCumulative);
            newObservation.timestamp = currentTime;
            upkeepConditionMet = true;
        }

        if (!upkeepConditionMet) revert("No upkeep condition met.");
    }

    //============================== ORACLE VIEW FUNCTIONS ===============================

    function getLatest() external view returns (uint256 ans, uint256 timeWeightedAverageAnswer, bool notSafeToUse) {
        // Check if upkeep is underfunded, if so set notSafeToUse to true, and return.

        // Check if answer is stale, if so set notSafeToUse to true, and return.
        uint256 timeDeltaSinceLastUpdated = block.timestamp - observations[currentIndex].timestamp;
        // Note add in the grace period here, because it can take time for the upkeep TX to go through.
        if (timeDeltaSinceLastUpdated > (heartbeat + gracePeriod)) return (0, 0, true);

        // Read state from one slot.
        ans = answer;
        uint16 _currentIndex = currentIndex;
        uint16 _observationsLength = observationsLength;

        // Scale results back down to cellar asset decimals.
        ans = ans.changeDecimals(SCALING_DECIMALS, decimals);

        (timeWeightedAverageAnswer, notSafeToUse) = _getTimeWeightedAverageAnswer(_currentIndex, _observationsLength);
        if (notSafeToUse) return (0, 0, true);
        timeWeightedAverageAnswer = timeWeightedAverageAnswer.changeDecimals(SCALING_DECIMALS, decimals);
    }

    //============================== INTERNAL HELPER FUNCTIONS ===============================

    function _getNextIndex(uint16 _currentIndex, uint16 _length) internal pure returns (uint16 nextIndex) {
        nextIndex = (_currentIndex == _length - 1) ? 0 : _currentIndex + 1;
    }

    function _getPreviousIndex(uint16 _currentIndex, uint16 _length) internal pure returns (uint16 previousIndex) {
        previousIndex = (_currentIndex == 0) ? _length - 1 : _currentIndex - 1;
    }

    // TODO if we make the slot optimization above, then pass in index to this function, we reduce gas costs by 2,100 for reads.
    function _getTimeWeightedAverageAnswer(
        uint16 _currentIndex,
        uint16 _observationsLength
    ) internal view returns (uint256 timeWeightedAverageAnswer, bool notSafeToUse) {
        // Read observations from storage.
        Observation memory mostRecentlyCompletedObservation = observations[
            _getPreviousIndex(_currentIndex, _observationsLength)
        ];
        Observation memory oldestObservation = observations[_getNextIndex(_currentIndex, _observationsLength)];

        // Data is not set.
        if (oldestObservation.timestamp == 1) return (0, true);

        uint256 timeDelta = mostRecentlyCompletedObservation.timestamp - oldestObservation.timestamp;
        /// @dev use _length - 2 because
        /// remove 1 because observations array stores the current pending observation.
        /// remove 1 because we are really interested in the time between observations.
        uint256 minDuration = heartbeat * (_observationsLength - 2);
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

    function _getTargetSharePrice() internal view returns (uint224 sharePrice) {
        uint256 totalShares = target.totalSupply();
        // Get total Assets but scale it up to SCALING_DECIMALS decimals of precision.
        uint256 totalAssets = target.totalAssets().changeDecimals(decimals, SCALING_DECIMALS);

        if (totalShares == 0) return 0;

        uint256 _sharePrice = ONE_SHARE.mulDivDown(totalAssets, totalShares);

        if (_sharePrice > type(uint224).max) revert("Share price too large");
        sharePrice = uint224(_sharePrice);
    }
}
