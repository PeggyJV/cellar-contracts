// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { IOracle } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IOracle.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { Math } from "src/utils/Math.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract MockDataFeedForMorphoBlue is IOracle {
    using Math for uint256;

    int256 public mockAnswer;
    uint256 public mockUpdatedAt;
    uint256 public price;
    uint256 constant ORACLE_PRICE_DECIMALS = 36; // from MorphoBlue
    uint256 constant CHAINLINK_PRICE_SCALE = 1e8;

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

    function setMockAnswer(int256 ans, ERC20 _collateralToken, ERC20 _loanToken) external {
        mockAnswer = ans;
        uint256 collateralDecimals = _collateralToken.decimals();
        uint256 loanTokenDecimals = _loanToken.decimals();
        _setPrice(uint256(ans), collateralDecimals, loanTokenDecimals);
    }

    function setMockUpdatedAt(uint256 at) external {
        mockUpdatedAt = at;
    }

    /**
     * @dev Takes the chainlink price, scales it down, then applies the appropriate scalar needed for morpho blue calcs.
     * NOTE: Recall from IOracle.sol that the units will be 10 ** (36 - collateralUnits + borrowUnits)
     */
    function _setPrice(uint256 _newPrice, uint256 _collateralDecimals, uint256 _loanTokenDecimals) internal {
        price =
            (_newPrice / CHAINLINK_PRICE_SCALE) *
            (10 ** (ORACLE_PRICE_DECIMALS - _collateralDecimals + _loanTokenDecimals)); // BU / CU
    }
}
