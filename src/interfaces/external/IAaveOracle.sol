// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IAaveOracle {
    function BASE_CURRENCY_UNIT() external view returns (uint256);

    function BASE_CURRENCY() external view returns (address);
}
