// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626SharePriceOracle, Math, ERC4626 } from "src/base/ERC4626SharePriceOracle.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

// TODO also there is nothing enforcing that the oracles on the two chains are configured with the same values.
// But we would really need to enforce this using a CCIP creation method like the cross chain shares, but this is more complicated
/**
 * @title MultiChainERC4626SharePriceOracleDestination
 * @notice Receives CCIP messages, and reports share pricing data.
 * @author crispymangoes
 */
contract MultiChainERC4626SharePriceOracleDestination is ERC4626SharePriceOracle, CCIPReceiver {
    using Math for uint256;

    // ========================================= CONSTANTS =========================================

    /**
     * @notice CCIP Message data used to indicate source oracles killSwitch was activated,
     *         so destination oracle should activate its killSwitch.
     */
    bytes public constant KILL_SWITCH_ACTIVATED_DATA = hex"DEAD";

    //============================== ERRORS ===============================

    error MultiChainERC4626SharePriceOracleDestination___SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error MultiChainERC4626SharePriceOracleDestination___SenderNotAllowlisted(address sender);
    error MultiChainERC4626SharePriceOracleDestination___NotSupported(); /// TODO test

    //============================== EVENTS ===============================

    /**
     * @notice Emitted when source oracle has its killSwitch activated, so this oracles killSwitch is activated.
     * @param timestamp unix timestamp when killSwitch was activated
     */
    event KillSwitchActivatedOnSource(uint256 timestamp);

    //============================== MODIFIERS ===============================

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != sourceChainSelector)
            revert MultiChainERC4626SharePriceOracleDestination___SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != sourceOracle)
            revert MultiChainERC4626SharePriceOracleDestination___SenderNotAllowlisted(_sender);
        _;
    }

    //============================== IMMUTABLES ===============================

    /**
     * @notice The address on source chain sending performData.
     */
    address public immutable sourceOracle;

    /**
     * @notice The CCIP chain selector of source chain.
     */
    uint64 public immutable sourceChainSelector;

    /**
     * @dev _target should be the DestinationMinter contract that was deployed from calling `SourceLockerFactory:deploy()`.
     */
    constructor(
        ERC4626 _target,
        uint64 _heartbeat,
        uint64 _deviationTrigger,
        uint64 _gracePeriod,
        uint16 _observationsToUse,
        address _link,
        uint216 _startingAnswer,
        uint256 _allowedAnswerChangeLower,
        uint256 _allowedAnswerChangeUpper,
        address _router,
        address _sourceOracle,
        uint64 _sourceChainSelector
    )
        ERC4626SharePriceOracle(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            address(0),
            address(0),
            address(0),
            _link,
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        )
        CCIPReceiver(_router)
    {
        sourceOracle = _sourceOracle;
        sourceChainSelector = _sourceChainSelector;
    }

    //============================== CHAINLINK AUTOMATION ===============================

    /**
     * @notice Automation is not supported
     */
    function checkUpkeep(bytes calldata) public pure override returns (bool, bytes memory) {
        revert MultiChainERC4626SharePriceOracleDestination___NotSupported();
    }

    /**
     * @notice Automation is not supported
     */
    function performUpkeep(bytes calldata) public pure override {
        revert MultiChainERC4626SharePriceOracleDestination___NotSupported();
    }

    //============================== CCIP RECEIVER ===============================

    /**
     * @notice Implement internal _ccipRecevie function logic.
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        if (
            any2EvmMessage.data.length == 2 && keccak256(any2EvmMessage.data) == keccak256(KILL_SWITCH_ACTIVATED_DATA)
        ) {
            killSwitch = true;
            emit KillSwitchActivatedOnSource(block.timestamp);
        } else {
            // Pass in false so we do not run killswitch checks.
            _performUpkeep(any2EvmMessage.data, false);
        }
    }
}
