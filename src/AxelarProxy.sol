// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AxelarExecutable } from "lib/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Axelar Proxy
 * @notice Allows for Cellars deployed on L2s to be controlled by the Sommelier Chain using Axelar messages.
 * @dev This contract will be deployed on some L2, then to run a Cellar on that L2,
 *      deploy the Cellar, and make this contract the owner.
 * @author crispymangoes
 */
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
     * @dev Verifies message is a valid Axelar message, otherwise reverts.
     *      See `AxelarExecutable.sol`.
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
     * @notice This contract is not setup to handle ERC20 tokens, so execution with token calls will revert.
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
