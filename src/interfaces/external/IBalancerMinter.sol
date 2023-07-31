// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IBalancerMinter {
    function mint(address gauge) external;
}
