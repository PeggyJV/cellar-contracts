// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { AxelarExecutable } from "lib/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract AxelarProxy is AxelarExecutable {
    using Address for address;

    event LogicCallEvent(address target, bytes callData);

    error AxelarProxy__WrongSource();
    error AxelarProxy__NoTokens();

    bytes32 public constant SOMMELIER_CHAIN_HASH = keccak256(bytes("sommelier"));

    constructor(address gateway_) AxelarExecutable(gateway_) {}

    /**
     * @notice Execution logic.
     * @dev Verifies message is from Sommelier, otherwise reverts.
     */
    function _execute(string calldata sourceChain, string calldata, bytes calldata payload) internal override {
        // Validate Source Chain
        if (keccak256(bytes(sourceChain)) != SOMMELIER_CHAIN_HASH) revert AxelarProxy__WrongSource();

        // Execute function call.
        (address target, bytes memory callData) = abi.decode(payload, (address, bytes));
        target.functionCall(callData);

        emit LogicCallEvent(target, callData);
    }

    /**
     * @notice Execution with token logic.
     * @dev Not supported.
     */
    function _executeWithToken(
        string calldata,
        string calldata,
        bytes calldata,
        string calldata,
        uint256
    ) internal pure override {
        revert AxelarProxy__NoTokens();
    }
}
