// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface ISTETH {
    function getPooledEthByShares(uint256 shares) external view returns (uint256);

    function decimals() external view returns (uint8);
}
