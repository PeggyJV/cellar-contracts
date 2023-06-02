// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { AxelarExecutable } from "lib/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Owned } from "@solmate/auth/Owned.sol";

contract AxelarProxy is AxelarExecutable, Owned {
    using Address for address;

    event LogicCallEvent(address target, bytes callData);

    error AxelarProxy__WrongSource();
    error AxelarProxy__NoTokens();
    error AxelarProxy__ExecutionStopped();

    bytes32 public constant SOMMELIER_CHAIN_HASH = keccak256(bytes("sommelier"));

    /**
     * @notice When true, prevents all Axelar calls.
     */
    bool public stopExecute;

    /**
     * @notice If stopExecute logic is not needed, use zero address for `owner`.
     */
    constructor(address gateway_, address owner) AxelarExecutable(gateway_) Owned(owner) {}

    /**
     * @notice Allows owner to block Axelar calls or allow them.
     */
    function toggleExecution() external onlyOwner {
        stopExecute = stopExecute ? false : true;
    }

    /**
     * @notice Execution logic.
     * @dev Verifies message is from Sommelier, otherwise reverts.
     */
    function _execute(string calldata sourceChain, string calldata, bytes calldata payload) internal override {
        // Make sure executions are still allowed.
        if (stopExecute) revert AxelarProxy__ExecutionStopped();

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
