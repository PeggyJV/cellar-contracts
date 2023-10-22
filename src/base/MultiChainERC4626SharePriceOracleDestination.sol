// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626SharePriceOracle, Math, ERC4626 } from "src/base/ERC4626SharePriceOracle.sol";

contract MultiChainERC4626SharePriceOracleDestination is ERC4626SharePriceOracle {
    using Math for uint256;

    constructor(
        ERC4626 _target,
        uint64 _heartbeat,
        uint64 _deviationTrigger,
        uint64 _gracePeriod,
        uint16 _observationsToUse,
        address _automationRegistry,
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
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        )
    {}

    //============================== CHAINLINK AUTOMATION ===============================

    function checkUpkeep(
        bytes calldata checkData
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        revert("not supported");
    }

    function performUpkeep(bytes calldata performData) external override {
        revert("not supported");
    }

    // TODO CCIP function to recieve messages from source then call _performUpkeep
    // Should only be callable by the ccip router, then needs to verify the message came from the source oracle, from the source chain.
}
