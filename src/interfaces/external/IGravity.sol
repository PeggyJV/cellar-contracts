// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IGravity {
    function sendToCosmos(address _tokenContract, bytes32 _destination, uint256 _amount) external;
}
