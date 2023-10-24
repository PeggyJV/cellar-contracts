// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IRegistry {
    function getForwarder(uint256 upkeepID) external view returns (address forwarder);
}