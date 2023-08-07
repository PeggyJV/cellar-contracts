// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface DSRManager {
    function join(address dst, uint256 amount) external;

    function exit(address dst, uint256 amount) external;

    function exitAll(address dst) external;

    function pieOf(address user) external view returns (uint256);

    function pot() external view returns (address);

    function dai() external view returns (address);

    function daiBalance(address user) external returns (uint256);
}
