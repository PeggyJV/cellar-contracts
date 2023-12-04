// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626SharePriceOracle, Math, ERC4626 } from "src/base/ERC4626SharePriceOracle.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

// TODO some important notes
// if the CCIP network is substantially delayed, then state can exist where only 1 oracle is shutdown
// additionally I could see situations in which the mainnet oracle could be shutdown from an update that was successful
// on the source chain because the TWAA answers at time of udpate will be different, but
// hopefully making the TWAA duration much longer than ccip send messages will mitigate this
// Also by noting that only relativey stable cellars will be made crosschain, IE we would never have a cross chain trading cellar, or curve cellar
// Also making the allowed answer change upper and lower a bit more generous.
// TODO also there is nothing enforcing that the oracles on the two chains are configured with the same values.
// But we would really need to enforce this using a CCIP creation method like the cross chain shares, but this is more complicated
contract MultiChainERC4626SharePriceOracleDestination is ERC4626SharePriceOracle, CCIPReceiver {
    using Math for uint256;

    error SourceChainNotAllowlisted(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowlisted(address sender); // Used when the sender has not been allowlisted by the contract owner.

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != sourceChainSelector) revert SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != sourceOracle) revert SenderNotAllowlisted(_sender);
        _;
    }

    address public immutable sourceOracle;
    uint64 public immutable sourceChainSelector;

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

    function checkUpkeep(bytes calldata) public pure override returns (bool, bytes memory) {
        revert("not supported");
    }

    function performUpkeep(bytes calldata) public pure override {
        revert("not supported");
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        (bytes memory performData, bool sourceKillSwitch) = abi.decode(any2EvmMessage.data, (bytes, bool));
        if (sourceKillSwitch) {
            // TODO emit an event
            killSwitch = true;
        } else {
            _performUpkeep(performData);
            // It is possible for this contracts killWwitch to be triggered, but not the sources.
            // block timestamp of kill switch calcualtions differing between source and dest.
            if (killSwitch) {
                killSwitch = false;
                // TODO emit an event that the kill switch was reset?
            }
        }
        // Test ideas
        // messages come in out of order
        // handle scenarios where kill switch is triggered.
    }
}
