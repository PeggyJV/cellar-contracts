// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { Math } from "src/utils/Math.sol";
import { Owned } from "@solmate/auth/Owned.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

contract ERC4626SharePriceOracle is AutomationCompatibleInterface {
    using Math for uint256;

    // ========================================= STRUCTS =========================================

    struct Observation {
        uint64 timestamp;
        uint192 cumulative;
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
     * @notice The length of the observations array.
     * @dev `observations` will never change itsw length once set in the constructor.
     *      By saving this value here, we can take advantage of variable packing to make reads cheaper.
     */
    uint16 public observationsLength;

    /**
     * @notice Stores the observations this contract uses to derive a
     *         time weighted average answer.
     */
    Observation[] public observations;

    /**
     * @notice Decimals used to scale share price for internal calculations.
     */
    uint8 public constant ORACLE_DECIMALS = 18;

    //============================== ERRORS ===============================
    error ERC4626SharePriceOracle__OnlyCallableByAutomationRegistry();
    error ERC4626SharePriceOracle__StalePerformData();
    error ERC4626SharePriceOracle__CumulativeTooLarge();
    error ERC4626SharePriceOracle__NoUpkeepConditionMet();
    error ERC4626SharePriceOracle__SharePriceTooLarge();

    //============================== IMMUTABLES ===============================

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
     * @notice Chainlink's Automation Registry contract address.
     * @notice For mainnet use 0x02777053d6764996e594c3E88AF1D58D5363a2e6.
     */
    address public immutable automationRegistry;

    /**
     * @notice ERC4626 target vault this contract is an oracle for.
     */
    ERC4626 public immutable target;

    /**
     * @notice Target vault decimals.
     */
    uint8 public immutable targetDecimals;

    // TODO add Automation V2.1 Upkeep creation code to the constructor, so that the upkeep ID can be saved, and upkeep balances can be checked during getLatest calls.
    /**
     * @notice TWAA Minimum Duration = `_observationsToUse` * `_heartbeat`.
     * @notice TWAA Maximum Duration = `_observationsToUse` * `_heartbeat` + `gracePeriod`.
     * @notice TWAA calculations will use the most recently completed observation,
     *         which can at most be ~heartbeat stale.
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
        targetDecimals = target.decimals();
        ONE_SHARE = 10 ** targetDecimals;
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

    /**
     * @notice Leverages Automation V2 secure offchain computation to run expensive share price calculations offchain,
     *         then inject them onchain using `performUpkeep`.
     */
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

    /**
     * @notice Save answer on chain, and update observations if needed.
     */
    function performUpkeep(bytes calldata performData) external {
        if (msg.sender != automationRegistry) revert ERC4626SharePriceOracle__OnlyCallableByAutomationRegistry();
        (uint224 sharePrice, uint64 currentTime) = abi.decode(performData, (uint224, uint64));

        // Verify atleast one of the upkeep conditions was met.
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
        if (currentObservation.timestamp >= currentTime) revert ERC4626SharePriceOracle__StalePerformData();

        // See if we are updating because of staleness.
        uint256 timeDelta = currentTime - currentObservation.timestamp;
        if (timeDelta >= heartbeat) upkeepConditionMet = true;

        uint256 currentCumulative = currentObservation.cumulative + (sharePrice * timeDelta);
        // TODO this check realistically is not needed, but can talk with auditors about it.
        if (currentCumulative > type(uint192).max) revert ERC4626SharePriceOracle__CumulativeTooLarge();
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

        if (!upkeepConditionMet) revert ERC4626SharePriceOracle__NoUpkeepConditionMet();
    }

    //============================== ORACLE VIEW FUNCTIONS ===============================

    /**
     * @notice Get the latest answer, time weighted average answer, and bool indicating whether they can be safely used.
     */
    function getLatest() external view returns (uint256 ans, uint256 timeWeightedAverageAnswer, bool notSafeToUse) {
        // TODO Check if upkeep is underfunded, if so set notSafeToUse to true, and return.

        // Check if answer is stale, if so set notSafeToUse to true, and return.
        uint256 timeDeltaSinceLastUpdated = block.timestamp - observations[currentIndex].timestamp;
        // Note add in the grace period here, because it can take time for the upkeep TX to go through.
        if (timeDeltaSinceLastUpdated > (heartbeat + gracePeriod)) return (0, 0, true);

        // Read state from one slot.
        ans = answer;
        uint16 _currentIndex = currentIndex;
        uint16 _observationsLength = observationsLength;

        (timeWeightedAverageAnswer, notSafeToUse) = _getTimeWeightedAverageAnswer(_currentIndex, _observationsLength);
        if (notSafeToUse) return (0, 0, true);
    }

    //============================== INTERNAL HELPER FUNCTIONS ===============================

    /**
     * @notice Get the next index of observations array.
     */
    function _getNextIndex(uint16 _currentIndex, uint16 _length) internal pure returns (uint16 nextIndex) {
        nextIndex = (_currentIndex == _length - 1) ? 0 : _currentIndex + 1;
    }

    /**
     * @notice Get the previous index of observations array.
     */
    function _getPreviousIndex(uint16 _currentIndex, uint16 _length) internal pure returns (uint16 previousIndex) {
        previousIndex = (_currentIndex == 0) ? _length - 1 : _currentIndex - 1;
    }

    /**
     * @notice Use observations to get the time weighted average answer.
     */
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
        // TODO we should realistically never hit this if we confirm observations always last a minimum of heartbeat.
        if (timeDelta < minDuration) return (0, true);
        // Data is too old
        if (timeDelta > maxDuration) return (0, true);

        timeWeightedAverageAnswer =
            (mostRecentlyCompletedObservation.cumulative - oldestObservation.cumulative) /
            timeDelta;
    }

    /**
     * @notice Get the target ERC4626's share price using totalAssets, and totalSupply.
     */
    function _getTargetSharePrice() internal view returns (uint224 sharePrice) {
        uint256 totalShares = target.totalSupply();
        // Get total Assets but scale it up to ORACLE_DECIMALS decimals of precision.
        uint256 totalAssets = target.totalAssets().changeDecimals(targetDecimals, ORACLE_DECIMALS);

        if (totalShares == 0) return 0;

        uint256 _sharePrice = ONE_SHARE.mulDivDown(totalAssets, totalShares);

        if (_sharePrice > type(uint224).max) revert ERC4626SharePriceOracle__SharePriceTooLarge();
        sharePrice = uint224(_sharePrice);
    }
}
