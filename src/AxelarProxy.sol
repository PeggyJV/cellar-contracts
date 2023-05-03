// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { AxelarExecutable } from "src/base/AxelarExecutable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract AxelarProxy is AxelarExecutable {
    using Address for address;

    event LogicCallEvent(address target, bytes callData);

    error AxelarProxy__NoTokens();
    error AxelarProxy__WrongSource();
    error AxelarProxy__WrongSender();

    bytes32 public immutable sourceChainHash;
    bytes32 public immutable sourceAddressHash;
    bytes32 public constant SOMMELIER_CHAIN_HASH = keccak256(bytes("Sommelier"));

    constructor(address gateway_, string memory sourceChain, string memory sourceAddress) AxelarExecutable(gateway_) {
        sourceChainHash = keccak256(bytes(sourceChain));
        sourceAddressHash = keccak256(bytes(sourceAddress));
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        // TODO this check might not be needed since `execute` calls `validateContractCallAndMint` on the gateway.
        // if (msg.sender != address(gateway)) revert AxelarProxy__NotTheGateway();

        // Validate Source Chain
        bytes32 _sourceChainHash = sourceChainHash;
        if (keccak256(bytes(sourceChain)) != _sourceChainHash) revert AxelarProxy__WrongSource();

        if (_sourceChainHash != SOMMELIER_CHAIN_HASH) {
            // Validate Sender.
            if (keccak256(bytes(sourceAddress)) != sourceAddressHash) revert AxelarProxy__WrongSender();
        }

        (address target, bytes memory callData) = abi.decode(payload, (address, bytes));
        target.functionCall(callData);

        emit LogicCallEvent(target, callData);
    }

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
