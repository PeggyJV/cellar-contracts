// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

interface ICurveSwaps {
    function exchange_multiple(
        address[9] memory _route,
        uint256[3][4] memory _swap_params,
        uint256 _amount,
        uint256 _expected
    ) external returns (uint256);
}