// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IRedstoneClassicPriceFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
