// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

contract MockAxelarGateway {
    function validateContractCall(bytes32, string calldata, string calldata, bytes32) external pure returns (bool) {
        return true;
    }
}
