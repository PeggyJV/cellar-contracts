// SPDX-License-Identifier: ISC
pragma solidity >=0.8.16;

interface IRateCalculator {
    function name() external pure returns (string memory);

    function requireValidInitData(bytes calldata _initData) external pure;

    function getConstants() external pure returns (bytes memory _calldata);

    function getNewRate(bytes calldata _data, bytes calldata _initData) external pure returns (uint64 _newRatePerSec);
}
