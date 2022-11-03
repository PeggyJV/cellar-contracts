// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface ICurvePool {
    function coins(uint256 i) external view returns (address);

    function get_virtual_price() external view returns (uint256);
}
