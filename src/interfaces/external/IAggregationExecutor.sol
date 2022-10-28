// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IAggregationExecutor {
    /// @notice Make calls on `msgSender` with specified data
    function callBytes(address msgSender, bytes calldata data) external payable; // 0x2636f7f8
}
