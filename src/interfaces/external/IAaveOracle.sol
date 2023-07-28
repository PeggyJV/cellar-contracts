// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IAaveOracle {
    function BASE_CURRENCY_UNIT() external view returns (uint256);

    function BASE_CURRENCY() external view returns (address);

    function getAssetPrice(address asset) external view returns (uint256);
}
