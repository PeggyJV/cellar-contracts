// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { AxelarExecutable } from "src/base/AxelarExecutable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract AxelarProxy is AxelarExecutable {
    using Address for address;

    constructor(address gateway_) AxelarExecutable(gateway_) {}

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        // TODO this check might not be needed since `execute` calls `validateContractCallAndMint` on the gateway.
        if (msg.sender != address(gateway)) revert("Not the gateway");
        // Validate Source Chain
        if (keccak256(bytes(sourceChain)) != keccak256(bytes("Sommelier"))) revert("Wrong source");
        // Validate source address or maybe not

        (address target, bytes memory callData) = abi.decode(payload, (address, bytes));
        target.functionCall(callData);
    }

    function _executeWithToken(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal override {
        revert("No tokens");
    }
}
