// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626SharePriceOracle, Math, ERC4626, ERC20 } from "src/base/ERC4626SharePriceOracle.sol";
import { IRouterClient } from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

/**
 * @title MultiChainERC4626SharePriceOracleSource
 * @notice Uses CCIP to relay share pricing data to a destination chain.
 * @author crispymangoes
 */
contract MultiChainERC4626SharePriceOracleSource is ERC4626SharePriceOracle {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    // ========================================= CONSTANTS =========================================

    /**
     * @notice CCIP Message data used to indicate source oracles killSwitch was activated,
     *         so destination oracle should activate its killSwitch.
     */
    bytes public constant KILL_SWITCH_ACTIVATED_DATA = hex"DEAD";

    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice CCIP Router for current network.
     */
    IRouterClient public router;

    /**
     * @notice The address of the destination oracle, on destination chain.
     */
    address public destinationOracle;

    /**
     * @notice The CCIP chain selector of destination chain.
     */
    uint64 public destinationChainSelector;

    //============================== ERRORS ===============================

    error MultiChainERC4626SharePriceOracleSource___KillSwitchNotActivated();
    error MultiChainERC4626SharePriceOracleSource___AlreadyInitialized(); // TODO check for revert
    error MultiChainERC4626SharePriceOracleSource___BadRouter(); // TODO check for revert
    error MultiChainERC4626SharePriceOracleSource___NotEnoughLink(); // TODO check for revert

    //============================== EVENTS ===============================

    /**
     * @notice Emitted when performData is forwarded to destination oracle.
     * @param messageId the ccip message id
     * @param timestamp the time the message was sent
     */
    event PerformDataSent(bytes32 messageId, uint256 timestamp);

    /**
     * @notice Emitted when this contracts killSwitch was activated, but it does not have enough funds to forward the message
     *         to destination oracle.
     */
    event KillSwitchActivatedButNotEnoughLinkToNotifyDestination();

    /**
     * @notice Emitted when this contracts killSwitch is activated, and the killSwitch message is sent to
     *         destination oracle.
     */
    event KillSwitchForwardedToDestination(bytes32 messageId, uint256 timestamp);

    //============================== IMMUTABLES ===============================

    constructor(
        ERC4626 _target,
        uint64 _heartbeat,
        uint64 _deviationTrigger,
        uint64 _gracePeriod,
        uint16 _observationsToUse,
        address _automationRegistry,
        address _automationRegistrar,
        address _automationAdmin,
        address _link,
        uint216 _startingAnswer,
        uint256 _allowedAnswerChangeLower,
        uint256 _allowedAnswerChangeUpper
    )
        ERC4626SharePriceOracle(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            _automationRegistrar,
            _automationAdmin,
            _link,
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        )
    {}

    //============================== ADMIN FUNCTIONS ===============================

    /**
     * @notice Admin should call this function as opposed to normal `initialize`.
     *         if normal `initialize` is called, admin needs to deploy a new oracle and try again.
     */
    function initializeWithCcipArgs(
        uint96 initialUpkeepFunds,
        address _router,
        address _destinationOracle,
        uint64 _destinationChainSelector
    ) external {
        // Initialize checks if caller is automation admin.
        initialize(initialUpkeepFunds);

        if (_router == address(0)) revert MultiChainERC4626SharePriceOracleSource___BadRouter();
        if (address(router) != address(0)) revert MultiChainERC4626SharePriceOracleSource___AlreadyInitialized();
        router = IRouterClient(_router);
        destinationOracle = _destinationOracle;
        destinationChainSelector = _destinationChainSelector;
    }

    // TODO add test for this and natspec
    function withdrawLink() external {
        if (msg.sender != automationAdmin) revert ERC4626SharePriceOracle__OnlyAdmin();

        uint256 linkBalance = link.balanceOf(address(this));
        link.safeTransfer(msg.sender, linkBalance);
    }

    //============================== CHAINLINK AUTOMATION ===============================

    /**
     * @notice Runs `ERC4626SharePriceOracle:_checkUpkeep()` logic, then if upkeep is needed
     *         it will do 1 of 2 things.
     *         1) If this oracle should have its killSwitch activated, it continues without checking LINK balance.
     *         2) If killSwitch is not activated, this contract confirms it has enough link to forward performData to destination.
     */
    function checkUpkeep(
        bytes calldata checkData
    ) public view override returns (bool upkeepNeeded, bytes memory performData) {
        (upkeepNeeded, performData) = _checkUpkeep(checkData);

        if (upkeepNeeded) {
            // Check if kill switch would be triggered.
            (uint216 sharePrice, ) = abi.decode(performData, (uint216, uint64));
            (uint256 timeWeightedAverageAnswer, bool isNotSafeToUse) = _getTimeWeightedAverageAnswer(
                sharePrice,
                currentIndex,
                observationsLength
            );
            if (
                _checkIfKillSwitchShouldBeTriggeredView(sharePrice, answer) ||
                (!isNotSafeToUse && _checkIfKillSwitchShouldBeTriggeredView(sharePrice, timeWeightedAverageAnswer))
            ) {
                // Do not run any message checks because we need this upkeep to go through.
                return (upkeepNeeded, performData);
            }

            Client.EVM2AnyMessage memory message = _buildMessage(performData, false);

            // Calculate fees required for message, and adjust upkeepNeeded
            // if contract does not have enough LINK to cover fee.
            uint256 fees = router.getFee(destinationChainSelector, message);
            if (fees > link.balanceOf(address(this))) upkeepNeeded = false;
        }
    }

    /**
     * @notice Verifies message sender is forwarder, runs `ERC4626SharePriceOracle:_performUpkeep()` logic,
     *         then builds message to send to destination.
     *         If killSwitch was activated
     *         - Message contains command telling destination to activate its killSwitch
     *         - If this contract has enough LINK to send killSwitch message to destination is will do it.
     *           If not it emits an event but succeeds.
     *         If killSwitch was not activated
     *         - Message contains performData used in performUpkeep.
     *         - If this contract does not have enough LINK to send message TX reverts.
     */
    function performUpkeep(bytes calldata performData) public override {
        if (msg.sender != automationForwarder) revert ERC4626SharePriceOracle__OnlyCallableByAutomationForwarder();
        _performUpkeep(performData, true);

        bool sourceKillSwitch = killSwitch;

        Client.EVM2AnyMessage memory message = _buildMessage(performData, sourceKillSwitch);

        // Calculate fees required for message.
        uint256 fees = router.getFee(destinationChainSelector, message);
        if (fees > link.balanceOf(address(this))) {
            if (sourceKillSwitch) {
                // KillSwitch was triggered but we do not have enough LINK to send the update TX.
                emit KillSwitchActivatedButNotEnoughLinkToNotifyDestination();
                return;
            } else {
                // WE dont have enough LINK to send the message.
                revert MultiChainERC4626SharePriceOracleSource___NotEnoughLink();
            }
        }

        link.safeApprove(address(router), fees);

        bytes32 messageId = router.ccipSend(destinationChainSelector, message);
        emit PerformDataSent(messageId, block.timestamp);
    }

    //============================== KILLSWITCH ACTIVATED ===============================

    /**
     * @notice Once killSwitch is activated anyone can call this function to activate killSwitch on destination oracle.
     * @dev This function can be called multiple times with no harm, other than wasted LINK.
     */
    function forwardKillSwitchStateToDestination() external {
        bool sourceKillSwitch = killSwitch;
        if (!sourceKillSwitch) revert MultiChainERC4626SharePriceOracleSource___KillSwitchNotActivated();

        bytes memory emptyPerformData;
        Client.EVM2AnyMessage memory message = _buildMessage(emptyPerformData, sourceKillSwitch);

        uint256 fees = router.getFee(destinationChainSelector, message);

        link.safeTransferFrom(msg.sender, address(this), fees);

        link.safeApprove(address(router), fees);

        bytes32 messageId = router.ccipSend(destinationChainSelector, message);

        emit KillSwitchForwardedToDestination(messageId, block.timestamp);
    }

    //============================== INTERNAL HELPER FUNCTIONS ===============================

    /**
     * @notice Build the CCIP message to send to destination oracle.
     */
    function _buildMessage(
        bytes memory performData,
        bool sourceKillSwitch
    ) internal view returns (Client.EVM2AnyMessage memory message) {
        // Send ccip message to other chain, revert if not enough link
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationOracle),
            data: _buildMessageData(performData, sourceKillSwitch),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: 200_000 /*, strict: false*/ })
            ),
            feeToken: address(link)
        });
    }

    /**
     * @notice Build the message data based off `sourceKillSwitch`.
     * @dev If killSwitch is activated, the messages should just tell the destination oracle to activate its killSwitch.
     */
    function _buildMessageData(
        bytes memory performData,
        bool sourceKillSwitch
    ) internal pure returns (bytes memory data) {
        if (sourceKillSwitch) data = KILL_SWITCH_ACTIVATED_DATA;
        else {
            // We are not trying to activate killswitch, so just use performData.
            data = performData;
        }
    }
}
