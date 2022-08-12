// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { FeedRegistryInterface } from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
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

    /**
     * @notice Could not find an asset's price in USD or ETH.
     * @param asset address of the asset
     */
    error ChainlinkPriceFeedAdaptor__PriceNotAvailable(address asset);

    /**
     * @notice Interacts with Chainlink feed registry and first tries to get `asset` price in USD,
     *         if that fails, then it tries to get `asset` price in ETH, and then converts the answer into USD.
     * @param asset the ERC20 token to get the price of.
     * @return price the price of `asset` in USD
     * @return timestamp the last timestamp the price was updated by Chainlink nodes
     */
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
            try feedRegistry.latestRoundData(address(asset), Denominations.ETH) returns (
                uint80,
                int256 _price,
                uint256,
                uint256 _timestamp,
                uint80
            ) {
                // Change quote from ETH to USD.
                price = _price.toUint256().mulWadDown(_getExchangeRateFromETHToUSD());
                timestamp = _timestamp;
            } catch {
                revert ChainlinkPriceFeedAdaptor__PriceNotAvailable(address(asset));
            }
        }
    }

    /**
     * @notice Could not find an asset's price range in USD or ETH.
     * @param asset address of the asset
     */
    error ChainlinkPriceFeedAdaptor__PriceRangeNotAvailable(address asset);

    /**
     * @notice Interacts with Chainlink feed registry and first tries to get `asset` price range in USD,
     *         if that fails, then it tries to get `asset` price range in ETH, and then converts the range into USD.
     * @param asset the ERC20 token to get the price range of.
     * @return min the minimum price where Chainlink nodes stop updating the oracle
     * @return max the maximum price where Chainlink nodes stop updating the oracle
     */
    function _getPriceRangeInUSD(ERC20 asset) internal view returns (uint256 min, uint256 max) {
        try feedRegistry.getFeed(address(asset), Denominations.USD) returns (AggregatorV2V3Interface aggregator) {
            IChainlinkAggregator chainlinkAggregator = IChainlinkAggregator(address(aggregator));

            min = uint256(uint192(chainlinkAggregator.minAnswer()));
            max = uint256(uint192(chainlinkAggregator.maxAnswer()));
        } catch {
            // If we can't find the USD price, then try the ETH price.
            try feedRegistry.getFeed(address(asset), Denominations.ETH) returns (AggregatorV2V3Interface aggregator) {
                IChainlinkAggregator chainlinkAggregator = IChainlinkAggregator(address(aggregator));

                min = uint256(uint192(chainlinkAggregator.minAnswer()));
                max = uint256(uint192(chainlinkAggregator.maxAnswer()));

                // Change quote from ETH to USD.
                uint256 exchangeRateFromETHToUSD = _getExchangeRateFromETHToUSD();
                min = min.mulWadDown(exchangeRateFromETHToUSD);
                max = max.mulWadDown(exchangeRateFromETHToUSD);
            } catch {
                revert ChainlinkPriceFeedAdaptor__PriceRangeNotAvailable(address(asset));
            }
        }
    }

    /**
     * @notice helper function to grab pricing data for ETH in USD
     * @return exchangeRate the exchange rate for ETH in terms of USD
     */
    function _getExchangeRateFromETHToUSD() internal view returns (uint256 exchangeRate) {
        exchangeRate = uint256(feedRegistry.latestAnswer(Denominations.ETH, Denominations.USD));
    }
}
