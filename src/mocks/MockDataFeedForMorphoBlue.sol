// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { IOracle } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IOracle.sol";

contract MockDataFeedForMorphoBlue is IOracle {
    int256 public mockAnswer;
    uint256 public mockUpdatedAt;
    uint256 public price;
    uint256 constant ORACLE_PRICE_SCALE = 1e36; // from MorphoBlue

    IChainlinkAggregator public immutable realFeed;

    constructor(address _realFeed) {
        realFeed = IChainlinkAggregator(_realFeed);
    }

    function aggregator() external view returns (address) {
        return realFeed.aggregator();
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = realFeed.latestRoundData();
        if (mockAnswer != 0) answer = mockAnswer;
        if (mockUpdatedAt != 0) updatedAt = mockUpdatedAt;
    }

    function latestAnswer() external view returns (int256 answer) {
        answer = realFeed.latestAnswer();
        if (mockAnswer != 0) answer = mockAnswer;
    }

    function setMockAnswer(int256 ans) external {
        mockAnswer = ans;
        _setPrice(uint256(ans));
    }

    function setMockUpdatedAt(uint256 at) external {
        mockUpdatedAt = at;
    }

    function _setPrice(uint256 newPrice) internal {
        price = newPrice * ORACLE_PRICE_SCALE;
    }
}
