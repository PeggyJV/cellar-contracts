// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IBalancerMinter {
    function mint(address gauge) external;
}