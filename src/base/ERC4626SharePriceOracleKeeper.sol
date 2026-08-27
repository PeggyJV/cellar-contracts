// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @notice An ERC4626SharePriceOracle driven by a trusted keeper rather than
 *         Chainlink Automation, for networks where Automation is unavailable.
 *
 * @dev Two differences from the base contract, and no others:
 *
 *      1. `automationForwarder` is set in the constructor instead of by
 *         `initialize`. That makes `initialize` permanently unreachable, since
 *         it reverts once `automationForwarder` is non-zero. No Chainlink
 *         upkeep is ever registered and the oracle never needs LINK.
 *
 *      2. `performUpkeep` derives the answer from the target via
 *         `_getTargetSharePrice()` instead of decoding it out of `performData`.
 *         Chainlink documents `performData` as untrusted; the base contract
 *         relies on the forwarder to vouch for it. Deriving it on-chain means
 *         the keeper chooses only *when* an observation is taken, never *what*
 *         it says.
 *
 *      The upkeep body below is copied verbatim from the base contract so it
 *      diffs cleanly against the audited original. Every other safety property
 *      is inherited untouched: the TWAP ring buffer, `deviationTrigger`, the
 *      kill switch, heartbeat/grace staleness, and the sequencer check.
 *
 *      The keeper is trusted for liveness only. If it stops calling
 *      `performUpkeep`, `getLatest` reports `notSafeToUse` once the answer ages
 *      past `heartbeat + gracePeriod` - the same behaviour as Chainlink halting.
 */
contract ERC4626SharePriceOracleKeeper is ERC4626SharePriceOracle {
    using Math for uint256;

    /**
     * @notice Thrown when deployed with a zero keeper address.
     * @dev `automationForwarder` has no setter, so a zero keeper would brick the
     *      oracle permanently: no caller can ever satisfy `msg.sender == address(0)`.
     */
    error ERC4626SharePriceOracleKeeper__ZeroKeeper();

    constructor(ConstructorArgs memory args, address keeper) ERC4626SharePriceOracle(args) {
        if (keeper == address(0)) revert ERC4626SharePriceOracleKeeper__ZeroKeeper();
        automationForwarder = keeper;
    }

    /**
     * @notice Save answer on chain, and update observations if needed.
     * @dev `performData` is ignored; the answer is read from `target`.
     */
    function performUpkeep(bytes calldata) external override {
        if (msg.sender != automationForwarder) revert ERC4626SharePriceOracle__OnlyCallableByAutomationForwarder();
        // The only deviation from the base contract: the answer and its
        // timestamp come from chain state, not from the caller.
        uint216 sharePrice = _getTargetSharePrice();
        uint64 currentTime = uint64(block.timestamp);

        // Verify atleast one of the upkeep conditions was met.
        bool upkeepConditionMet;

        // Read state from one slot.
        uint256 _answer = answer;
        uint16 _currentIndex = currentIndex;
        uint16 _observationsLength = observationsLength;
        bool _killSwitch = killSwitch;

        if (_killSwitch) revert ERC4626SharePriceOracle__ContractKillSwitch();

        // See if kill switch should be activated based on change between answers.
        if (_checkIfKillSwitchShouldBeTriggered(sharePrice, _answer)) return;

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
        if (currentTime <= currentObservation.timestamp) revert ERC4626SharePriceOracle__StalePerformData();

        // Make sure time is not in the future.
        if (currentTime > block.timestamp) revert ERC4626SharePriceOracle__FuturePerformData();

        // See if we are updating because of staleness.
        uint256 timeDelta = currentTime - currentObservation.timestamp;
        if (timeDelta >= heartbeat) upkeepConditionMet = true;

        // Use the old answer to calculate cumulative.
        uint256 currentCumulative = currentObservation.cumulative + (_answer * timeDelta);
        if (currentCumulative > type(uint192).max) revert ERC4626SharePriceOracle__CumulativeTooLarge();
        currentObservation.cumulative = uint192(currentCumulative);
        currentObservation.timestamp = currentTime;

        uint256 timeDeltaSincePreviousObservation = currentTime -
            observations[_getPreviousIndex(_currentIndex, _observationsLength)].timestamp;
        // See if we need to advance to the next cumulative.
        if (timeDeltaSincePreviousObservation >= heartbeat) {
            uint16 nextIndex = _getNextIndex(_currentIndex, _observationsLength);
            currentIndex = nextIndex;
            // Update memory variable for event.
            _currentIndex = nextIndex;
            // Update newest cumulative.
            Observation storage newObservation = observations[nextIndex];
            newObservation.cumulative = uint192(currentCumulative);
            newObservation.timestamp = currentTime;
            upkeepConditionMet = true;
        }

        if (!upkeepConditionMet) revert ERC4626SharePriceOracle__NoUpkeepConditionMet();

        (uint256 timeWeightedAverageAnswer, bool isNotSafeToUse) = _getTimeWeightedAverageAnswer(
            sharePrice,
            _currentIndex,
            _observationsLength
        );

        // See if kill switch should be activated based on change between proposed answer and time weighted average answer.
        if (!isNotSafeToUse && _checkIfKillSwitchShouldBeTriggered(sharePrice, timeWeightedAverageAnswer)) return;
        emit OracleUpdated(block.timestamp, currentTime, sharePrice, timeWeightedAverageAnswer, isNotSafeToUse);
    }
}
