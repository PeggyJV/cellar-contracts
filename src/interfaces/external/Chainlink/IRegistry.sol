// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IRegistry {
    struct UpkeepInfo {
        address target;
        uint32 executeGas;
        bytes checkData;
        uint96 balance;
        address admin;
        uint64 maxValidBlocknumber;
        uint32 lastPerformBlockNumber;
        uint96 amountSpent;
        bool paused;
        bytes offchainConfig;
    }

    function getForwarder(uint256 upkeepID) external view returns (address forwarder);

    function getUpkeep(uint256 id) external view returns (UpkeepInfo memory upkeepInfo);
}
