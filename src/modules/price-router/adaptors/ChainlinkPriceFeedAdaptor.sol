// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { FeedRegistryInterface } from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";

contract ChainlinkPriceFeedAdaptor {
    using SafeCast for int256;
    using Math for uint256;

    /**
     * @notice Feed Registry contract used to get chainlink data feeds, use getFeed!!
     */
    FeedRegistryInterface public constant feedRegistry =
        FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);

    // =========================================== HELPER FUNCTIONS ===========================================

    function _getValueInUSDAndTimestamp(ERC20 asset) internal view returns (uint256 price, uint256 timestamp) {
        try feedRegistry.latestRoundData(address(asset), Denominations.USD) returns (
            uint80,
            int256 _price,
            uint256,
            uint256 _timestamp,
            uint80
        ) {
            price = _price.toUint256();
            timestamp = _timestamp;
        } catch {
            // If we can't find the USD price, then try the ETH price.
            (, int256 _price, , uint256 _timestamp, ) = feedRegistry.latestRoundData(address(asset), Denominations.ETH);

            // Change quote from ETH to USD.
            price = _price.toUint256().mulWadDown(_getExchangeRateFromETHToUSD());
            timestamp = _timestamp;
        }
    }

    function _getPriceRangeInUSD(ERC20 asset) internal view returns (uint256 min, uint256 max) {
        try feedRegistry.getFeed(address(asset), Denominations.USD) returns (AggregatorV2V3Interface aggregator) {
            IChainlinkAggregator chainlinkAggregator = IChainlinkAggregator(address(aggregator));

            min = uint256(uint192(chainlinkAggregator.minAnswer()));
            max = uint256(uint192(chainlinkAggregator.maxAnswer()));
        } catch {
            // If we can't find the USD price, then try the ETH price.
            AggregatorV2V3Interface aggregator = feedRegistry.getFeed(address(asset), Denominations.ETH);
            IChainlinkAggregator chainlinkAggregator = IChainlinkAggregator(address(aggregator));

            min = uint256(uint192(chainlinkAggregator.minAnswer()));
            max = uint256(uint192(chainlinkAggregator.maxAnswer()));

            // Change quote from ETH to USD.
            uint256 exchangeRateFromETHToUSD = _getExchangeRateFromETHToUSD();
            min = min.mulWadDown(exchangeRateFromETHToUSD);
            max = max.mulWadDown(exchangeRateFromETHToUSD);
        }
    }

    function _getExchangeRateFromETHToUSD() internal view returns (uint256 exchangeRate) {
        exchangeRate = uint256(feedRegistry.latestAnswer(Denominations.ETH, Denominations.USD));
    }
}
