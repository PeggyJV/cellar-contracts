// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

interface ICurveSwaps {
    function exchange(
        address _pool,
        address _from,
        address _to,
        uint256 _amount,
        uint256 _expected,
        address _receiver
    ) external returns (uint256);
}