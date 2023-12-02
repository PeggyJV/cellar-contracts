// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626SharePriceOracle, Math, ERC4626 } from "src/base/ERC4626SharePriceOracle.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

contract MultiChainERC4626SharePriceOracleSource is ERC4626SharePriceOracle {
    using Math for uint256;

    IRouterClient public router;
    address public destinationOracle;
    uint64 public destinationChainSelector;

    event PerformDataSent(bytes32 messageId, uint256 timestamp);

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

    function initializeWithCcipArgs(
        uint96 initialUpkeepFunds,
        address _router,
        address _destinationOracle,
        uint64 _destinationChainSelector
    ) external {
        // Initialize checks if caller is automation admin.
        initialize(initialUpkeepFunds);

        if (_router == address(0)) revert("Bad Router");
        if (address(router) != address(0)) revert("Already set");
        router = IRouterClient(_router);
        destinationOracle = _destinationOracle;
        destinationChainSelector = _destinationChainSelector;
    }

    //============================== CHAINLINK AUTOMATION ===============================

    // TODO want to handle scenarios where this one wants to shutdown but it doesn't have enough link to send the CCIP message.
    function checkUpkeep(
        bytes calldata checkData
    ) public view override returns (bool upkeepNeeded, bytes memory performData) {
        (upkeepNeeded, performData) = _checkUpkeep(checkData);

        if (upkeepNeeded) {
            // TODO if cellar is shutdown we want it to stay shutdown but allow 3rd party to send a special ccip shutdown message.
            // Check that contract has enough LINK to send ccip message
            // Could require a min share price
            Client.EVM2AnyMessage memory message = _buildMessage(performData);

            // Calculate fees required for message, and adjust upkeepNeeded
            // if contract does not have enough LINK to cover fee.
            uint256 fees = router.getFee(destinationChainSelector, message);
            if (fees > link.balanceOf(address(this))) upkeepNeeded = false;
        }
    }

    // TODO what does chainlink do if they quote $10 for an update
    // but in reality TX will cost $100

    function performUpkeep(bytes calldata performData) public override {
        if (msg.sender != automationForwarder) revert ERC4626SharePriceOracle__OnlyCallableByAutomationForwarder();
        _performUpkeep(performData);

        Client.EVM2AnyMessage memory message = _buildMessage(performData);

        // Calculate fees required for message.
        uint256 fees = router.getFee(destinationChainSelector, message);
        if (fees > link.balanceOf(address(this))) revert("Not enough Link");

        link.approve(address(router), fees);

        bytes32 messageId = router.ccipSend(destinationChainSelector, message);
        emit PerformDataSent(messageId, block.timestamp);
    }

    // TODO make data to be performData, and killswitch.
    function _buildMessage(bytes memory performData) internal view returns (Client.EVM2AnyMessage memory message) {
        // Send ccip message to other chain, revert if not enough link
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationOracle),
            data: performData,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: 200_000 /*, strict: false*/ })
            ),
            feeToken: address(link)
        });
    }
}
