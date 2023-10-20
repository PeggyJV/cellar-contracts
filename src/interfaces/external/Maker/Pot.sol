// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface Pot {
    function chi() external view returns (uint256);

    function drip() external;
}
