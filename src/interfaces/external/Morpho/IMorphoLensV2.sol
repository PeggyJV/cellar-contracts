// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IMorphoLensV2 {
    function getUserHealthFactor(address user) external view returns (uint256);
}
