// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Math } from "src/utils/Math.sol";
import { Owned } from "@solmate/auth/Owned.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import { IRegistrar } from "src/interfaces/external/Chainlink/IRegistrar.sol";
import { IRegistry } from "src/interfaces/external/Chainlink/IRegistry.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

contract ERC4626SharePriceOracle is AutomationCompatibleInterface {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    // ========================================= STRUCTS =========================================

    struct Observation {
        uint64 timestamp;
        uint192 cumulative;
    }

    /**
     * @notice Use a struct for constructor args so we do not encounter stack too deep errors.
     */
    struct ConstructorArgs {
        ERC4626 _target;
        uint64 _heartbeat;
        uint64 _deviationTrigger;
        uint64 _gracePeriod;
        uint16 _observationsToUse;
        address _automationRegistry;
        address _automationRegistrar;
        address _automationAdmin;
        address _link;
        uint216 _startingAnswer;
        uint256 _allowedAnswerChangeLower;
        uint256 _allowedAnswerChangeUpper;
        address _sequencerUptimeFeed;
        uint64 _sequencerGracePeriod;
    }

    // ========================================= CONSTANTS =========================================
    /**
     * @notice Gas Limit to use for Upkeep created in `initialize`.
     * @dev Should be fairly constant between networks, but 50_000 is a safe limit in
     *      most situations.
     */
    uint32 public constant UPKEEP_GAS_LIMIT = 50_000;

    /**
     * @notice Decimals used to scale share price for internal calculations.
     */
    uint8 public constant decimals = 18;

    // ========================================= GLOBAL STATE =========================================
    /**
     * @notice The latest stored onchain answer.
     */
    uint216 public answer;

    /**
     * @notice Stores the index of observations with the pending Observation.
     */
    uint16 public currentIndex;

    /**
     * @notice The length of the observations array.
     * @dev `observations` will never change its length once set in the constructor.
     *      By saving this value here, we can take advantage of variable packing to make reads cheaper.
     * @dev This is not immutable to make it easier in the future to create oracles that can expand their observations.
     */
    uint16 public observationsLength;

    /**
     * @notice Triggered when answer provided by Chainlink Automation is extreme.
     * @dev true: No further upkeeps are allowed, `getLatest` and `getLatestAnswer` will return true error bools.
     *      false: Continue as normal.
     */
    bool public killSwitch;

    /**
     * @notice Stores the observations this contract uses to derive a
     *         time weighted average answer.
     */
    Observation[] public observations;

    /**
     * @notice The Automation V2 Forwarder address for this contract.
     */
    address public automationForwarder;

    /**
     * @notice keccak256 hash of the parameters used to create this upkeep.
     * @dev Only set if `initialize` leads to a pending upkeep.
     */
    bytes32 public pendingUpkeepParamHash;

    //============================== ERRORS ===============================

    error ERC4626SharePriceOracle__OnlyCallableByAutomationForwarder();
    error ERC4626SharePriceOracle__StalePerformData();
    error ERC4626SharePriceOracle__CumulativeTooLarge();
    error ERC4626SharePriceOracle__NoUpkeepConditionMet();
    error ERC4626SharePriceOracle__SharePriceTooLarge();
    error ERC4626SharePriceOracle__FuturePerformData();
    error ERC4626SharePriceOracle__ContractKillSwitch();
    error ERC4626SharePriceOracle__AlreadyInitialized();
    error ERC4626SharePriceOracle__ParamHashDiffers();
    error ERC4626SharePriceOracle__NoPendingUpkeepToHandle();

    //============================== EVENTS ===============================

    /**
     * @notice Emitted when performUpkeep is ran.
     * @param timeUpdated the time the answer was updated on chain
     * @param timeAnswerCalculated the time the answer was calculated in checkUpkeep
     * @param latestAnswer the new answer
     * @param timeWeightedAverageAnswer the new time weighted average answer
     * @param isNotSafeToUse bool
     *                       if true: `timeWeightedAverageAnswer` is illogical, use `latestAnswer`
     *                       if false: use `timeWeightedAverageAnswer`
     */
    event OracleUpdated(
        uint256 timeUpdated,
        uint256 timeAnswerCalculated,
        uint256 latestAnswer,
        uint256 timeWeightedAverageAnswer,
        bool isNotSafeToUse
    );

    /**
     * @notice Emitted when the oracles kill switch is activated.
     * @dev If this happens, then the proposed performData lead to extremely volatile share price,
     *      so we need to investigate why that happened, mitigate it, then launch a new share price oracle.
     */
    event KillSwitchActivated(uint256 reportedAnswer, uint256 minAnswer, uint256 maxAnswer);

    /**
     * @notice Emitted when the upkeep is registered.
     */
    event UpkeepRegistered(uint256 upkeepId, address forwarder);

    /**
     * @notice Emitted when a upkeep registration is left pending.
     */
    event UpkeepPending(bytes32 upkeepParamHash);

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
     *      When calculating the TWAA, the total time delta for completed observations must be greater than 3 days but less than
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
     * @notice The admin address for the Automation Upkeep.
     */
    address public immutable automationAdmin;

    /**
     * @notice Chainlink's Automation Registry contract address.
     * @notice For mainnet use 0x6593c7De001fC8542bB1703532EE1E5aA0D458fD.
     */
    address public immutable automationRegistry;

    /**
     * @notice Chainlink's Automation Registrar contract address.
     * @notice For mainnet use 0x6B0B234fB2f380309D47A7E9391E29E9a179395a.
     */
    address public immutable automationRegistrar;

    /**
     * @notice Link Token.
     * @notice For mainnet use 0x514910771AF9Ca656af840dff83E8264EcF986CA.
     */
    ERC20 public immutable link;

    /**
     * @notice ERC4626 target vault this contract is an oracle for.
     */
    ERC4626 public immutable target;

    /**
     * @notice Target vault decimals.
     */
    uint8 public immutable targetDecimals;

    /**
     * @notice Multiplier with 4 decimals that determines the acceptable lower band
     *         for a performUpkeep answer.
     */
    uint256 public immutable allowedAnswerChangeLower;

    /**
     * @notice Multiplier with 4 decimals that determines the acceptable upper band
     *         for a performUpkeep answer.
     */
    uint256 public immutable allowedAnswerChangeUpper;

    /**
     * @notice Address for the networks sequencer uptime feed.
     * @dev For oracles that do not rely on a sequencer being up, use address(0).
     */
    IChainlinkAggregator internal immutable sequencerUptimeFeed;

    /**
     * @notice The grace period to enforce after a sequencer comes back online.
     * @dev Calls to `getLatest` and `getLatestAnswer` will return a true for
     *      `isNotSafeToUse` if the sequencer is down, or if the time since the
     *      sequencer went back online is less than `sequencerGracePeriod`.
     */
    uint64 public immutable sequencerGracePeriod;

    /**
     * @notice TWAA Minimum Duration = `_observationsToUse` * `_heartbeat`.
     * @notice TWAA Maximum Duration = `_observationsToUse` * `_heartbeat` + `gracePeriod` + `_heartbeat`.
     * @notice TWAA calculations will use the current pending observation, and then `_observationsToUse` observations.
     */
    constructor(ConstructorArgs memory args) {
        target = args._target;
        targetDecimals = target.decimals();
        ONE_SHARE = 10 ** targetDecimals;
        heartbeat = args._heartbeat;
        deviationTrigger = args._deviationTrigger;
        gracePeriod = args._gracePeriod;
        // Add 1 to observations to use.
        args._observationsToUse = args._observationsToUse + 1;
        observationsLength = args._observationsToUse;

        // Grow Observations array to required length, and fill it with observations that use 1 for timestamp and cumulative.
        // That way the initial upkeeps won't need to change state from 0 which is more expensive.
        for (uint256 i; i < args._observationsToUse; ++i)
            observations.push(Observation({ timestamp: 1, cumulative: 1 }));

        // Set to args._startingAnswer so slot is dirty for first upkeep, and does not trigger kill switch.
        answer = args._startingAnswer;

        if (args._allowedAnswerChangeLower > 1e4) revert("Illogical Lower");
        allowedAnswerChangeLower = args._allowedAnswerChangeLower;
        if (args._allowedAnswerChangeUpper < 1e4) revert("Illogical Upper");
        allowedAnswerChangeUpper = args._allowedAnswerChangeUpper;

        automationRegistry = args._automationRegistry;
        automationRegistrar = args._automationRegistrar;
        automationAdmin = args._automationAdmin;
        link = ERC20(args._link);
        sequencerUptimeFeed = IChainlinkAggregator(args._sequencerUptimeFeed);
        sequencerGracePeriod = args._sequencerGracePeriod;
    }

    //============================== INITIALIZATION ===============================

    /**
     * @notice Should be called after contract creation.
     * @dev Creates a Chainlink Automation Upkeep, and set the `automationForwarder` address.
     */
    function initialize(uint96 initialUpkeepFunds) external {
        // This function is only callable once.
        if (automationForwarder != address(0) || pendingUpkeepParamHash != bytes32(0))
            revert ERC4626SharePriceOracle__AlreadyInitialized();

        link.safeTransferFrom(msg.sender, address(this), initialUpkeepFunds);

        // Create the upkeep.
        IRegistrar registrar = IRegistrar(automationRegistrar);
        IRegistry registry = IRegistry(automationRegistry);
        IRegistrar.RegistrationParams memory params = IRegistrar.RegistrationParams({
            name: string.concat(target.name(), " Share Price Oracle"),
            encryptedEmail: hex"",
            upkeepContract: address(this),
            gasLimit: UPKEEP_GAS_LIMIT,
            adminAddress: automationAdmin,
            triggerType: 0,
            checkData: hex"",
            triggerConfig: hex"",
            offchainConfig: hex"",
            amount: initialUpkeepFunds
        });

        link.safeApprove(automationRegistrar, initialUpkeepFunds);
        uint256 upkeepID = registrar.registerUpkeep(params);
        if (upkeepID > 0) {
            // Upkeep was successfully registered.
            address forwarder = registry.getForwarder(upkeepID);
            automationForwarder = forwarder;
            emit UpkeepRegistered(upkeepID, forwarder);
        } else {
            // Upkeep is pending.
            bytes32 paramHash = keccak256(
                abi.encode(
                    params.upkeepContract,
                    params.gasLimit,
                    params.adminAddress,
                    params.triggerType,
                    params.checkData,
                    params.offchainConfig
                )
            );
            pendingUpkeepParamHash = paramHash;
            emit UpkeepPending(paramHash);
        }
    }

    /**
     * @notice Finish setting forwarder address if `initialize` did not get an auto-approved upkeep.
     */
    function handlePendingUpkeep(uint256 _upkeepId) external {
        if (pendingUpkeepParamHash == bytes32(0) || automationForwarder != address(0))
            revert ERC4626SharePriceOracle__NoPendingUpkeepToHandle();

        IRegistry registry = IRegistry(automationRegistry);

        IRegistry.UpkeepInfo memory upkeepInfo = registry.getUpkeep(_upkeepId);
        // Build the param hash using upkeepInfo.
        // The upkeep id has 16 bytes of entropy, that need to be shifted out(16*8=128).
        // Then take the resulting number and only take the last byte of it to get the trigger type.
        uint8 triggerType = uint8(_upkeepId >> 128);
        bytes32 proposedParamHash = keccak256(
            abi.encode(
                upkeepInfo.target,
                upkeepInfo.executeGas,
                upkeepInfo.admin,
                triggerType,
                upkeepInfo.checkData,
                upkeepInfo.offchainConfig
            )
        );
        if (pendingUpkeepParamHash != proposedParamHash) revert ERC4626SharePriceOracle__ParamHashDiffers();

        // Hashes match, so finish initialization.
        address forwarder = registry.getForwarder(_upkeepId);
        automationForwarder = forwarder;
        emit UpkeepRegistered(_upkeepId, forwarder);
    }

    //============================== CHAINLINK AUTOMATION ===============================

    /**
     * @notice Leverages Automation V2 secure offchain computation to run expensive share price calculations offchain,
     *         then inject them onchain using `performUpkeep`.
     */
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        // Get target share price.
        uint216 sharePrice = _getTargetSharePrice();
        // Read state from one slot.
        uint256 _answer = answer;
        uint16 _currentIndex = currentIndex;
        uint16 _observationsLength = observationsLength;
        bool _killSwitch = killSwitch;

        if (!_killSwitch) {
            // See if we need to update because answer is stale or outside deviation.
            // Time since answer was last updated.
            uint256 timeDeltaCurrentAnswer = block.timestamp - observations[_currentIndex].timestamp;
            uint256 timeDeltaSincePreviousObservation = block.timestamp -
                observations[_getPreviousIndex(_currentIndex, _observationsLength)].timestamp;
            uint64 _heartbeat = heartbeat;

            if (
                timeDeltaCurrentAnswer >= _heartbeat ||
                timeDeltaSincePreviousObservation >= _heartbeat ||
                sharePrice > _answer.mulDivDown(1e4 + deviationTrigger, 1e4) ||
                sharePrice < _answer.mulDivDown(1e4 - deviationTrigger, 1e4)
            ) {
                // We need to update answer.
                upkeepNeeded = true;
                performData = abi.encode(sharePrice, uint64(block.timestamp));
            }
        } // else no upkeep is needed
    }

    /**
     * @notice Save answer on chain, and update observations if needed.
     */
    function performUpkeep(bytes calldata performData) external {
        if (msg.sender != automationForwarder) revert ERC4626SharePriceOracle__OnlyCallableByAutomationForwarder();
        (uint216 sharePrice, uint64 currentTime) = abi.decode(performData, (uint216, uint64));

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

    //============================== ORACLE VIEW FUNCTIONS ===============================

    /**
     * @notice Get the latest answer, time weighted average answer, and bool indicating whether they can be safely used.
     */
    function getLatest() external view returns (uint256 ans, uint256 timeWeightedAverageAnswer, bool notSafeToUse) {
        // Read state from one slot.
        ans = answer;
        uint16 _currentIndex = currentIndex;
        uint16 _observationsLength = observationsLength;
        bool _killSwitch = killSwitch;

        if (_killSwitch) return (0, 0, true);
        if (_checkSequencer()) return (0, 0, true);

        // Check if answer is stale, if so set notSafeToUse to true, and return.
        uint256 timeDeltaSinceLastUpdated = block.timestamp - observations[currentIndex].timestamp;
        // Note add in the grace period here, because it can take time for the upkeep TX to go through.
        if (timeDeltaSinceLastUpdated > (heartbeat + gracePeriod)) return (0, 0, true);

        (timeWeightedAverageAnswer, notSafeToUse) = _getTimeWeightedAverageAnswer(
            ans,
            _currentIndex,
            _observationsLength
        );
        if (notSafeToUse) return (0, 0, true);
    }

    /**
     * @notice Get the latest answer, and bool indicating whether answer is safe to use or not.
     */
    function getLatestAnswer() external view returns (uint256, bool) {
        uint256 _answer = answer;
        bool _killSwitch = killSwitch;

        if (_killSwitch) return (0, true);
        if (_checkSequencer()) return (0, true);

        // Check if answer is stale, if so set notSafeToUse to true, and return.
        uint256 timeDeltaSinceLastUpdated = block.timestamp - observations[currentIndex].timestamp;
        // Note add in the grace period here, because it can take time for the upkeep TX to go through.
        if (timeDeltaSinceLastUpdated > (heartbeat + gracePeriod)) return (0, true);

        return (_answer, false);
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
        uint256 _answer,
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

        // Make sure that the old observations we are using are not too stale.
        uint256 timeDelta = mostRecentlyCompletedObservation.timestamp - oldestObservation.timestamp;
        /// @dev use _length - 2 because
        /// remove 1 because observations array stores the current pending observation.
        /// remove 1 because we are really interested in the time between observations.
        uint256 minDuration = heartbeat * (_observationsLength - 2);
        uint256 maxDuration = minDuration + gracePeriod;
        // Data is too new
        if (timeDelta < minDuration) return (0, true);
        // Data is too old
        if (timeDelta > maxDuration) return (0, true);

        Observation memory latestObservation = observations[_currentIndex];
        uint192 latestCumulative = latestObservation.cumulative +
            uint192((_answer * (block.timestamp - latestObservation.timestamp)));

        timeWeightedAverageAnswer =
            (latestCumulative - oldestObservation.cumulative) /
            (block.timestamp - oldestObservation.timestamp);
    }

    /**
     * @notice Get the target ERC4626's share price using totalAssets, and totalSupply.
     */
    function _getTargetSharePrice() internal view returns (uint216 sharePrice) {
        uint256 totalShares = target.totalSupply();
        // Get total Assets but scale it up to decimals decimals of precision.
        uint256 totalAssets = target.totalAssets().changeDecimals(targetDecimals, decimals);

        if (totalShares == 0) return 0;

        uint256 _sharePrice = ONE_SHARE.mulDivDown(totalAssets, totalShares);

        if (_sharePrice > type(uint216).max) revert ERC4626SharePriceOracle__SharePriceTooLarge();
        sharePrice = uint216(_sharePrice);
    }

    /**
     * @notice Activate the kill switch if `proposedAnswer` is extreme when compared to `answerToCompareAgainst`
     * @return bool indicating whether calling function should immediately exit or not.
     */
    function _checkIfKillSwitchShouldBeTriggered(
        uint256 proposedAnswer,
        uint256 answerToCompareAgainst
    ) internal returns (bool) {
        if (
            proposedAnswer < answerToCompareAgainst.mulDivDown(allowedAnswerChangeLower, 1e4) ||
            proposedAnswer > answerToCompareAgainst.mulDivDown(allowedAnswerChangeUpper, 1e4)
        ) {
            killSwitch = true;
            emit KillSwitchActivated(
                proposedAnswer,
                answerToCompareAgainst.mulDivDown(allowedAnswerChangeLower, 1e4),
                answerToCompareAgainst.mulDivDown(allowedAnswerChangeUpper, 1e4)
            );
            return true;
        }
        return false;
    }

    /**
     * @notice Checks if the sequencer is down, or if the grace period is not met.
     * @return bool indicating if the sequencer has a problem
     */
    function _checkSequencer() internal view returns (bool) {
        if (address(sequencerUptimeFeed) != address(0)) {
            (, int256 sequencerAnswer, uint256 startedAt, , ) = sequencerUptimeFeed.latestRoundData();

            // This check should make TXs from L1 to L2 revert if someone tried interacting with the cellar while the sequencer is down.
            // Answer == 0: Sequencer is up
            // Answer == 1: Sequencer is down
            if (sequencerAnswer == 1) {
                return true;
            }

            // Make sure the grace period has passed after the
            // sequencer is back up.
            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= sequencerGracePeriod) {
                return true;
            }
        }

        // If we made it this far, the sequencer is fine, and or it is not set.
        return false;
    }
}
