// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface CurvePool {
    function price_oracle() external view returns (uint256);

    function price_oracle(uint256 k) external view returns (uint256);

    function coins(uint256 i) external view returns (address);
}
