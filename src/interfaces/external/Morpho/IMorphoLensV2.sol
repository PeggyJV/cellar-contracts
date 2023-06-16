// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IMorphoLensV2 {
    function getUserHealthFactor(address user) external view returns (uint256);
}
