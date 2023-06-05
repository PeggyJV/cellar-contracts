// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IRETH {
    function getExchangeRate() external view returns (uint256);
}
