// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { BaseAdaptor } from "./BaseAdaptor.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "src/interfaces/IChainlinkAggregator.sol";

//TODO when converting int's to uint's does V8 check if the value is negative, or if its too large to fit into 128 bits?
//TODO does this even make sense to have a base adaptor? What functionality would all the adaptors share?
//TODO add in Math for easy decimal conversion
//TODO edge case where WBTC ~ BTC should we do a conversion from WBTC to BTC? How likely is a WBTC depeg?
//TODO maybe we should store a min/max vlaue directly tied to chainlink
contract ChainlinkPriceFeedAdaptor {
    address public constant USD = address(840); //used by feed registry to denominate USD
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Feed Registry contract used to get chainlink data feeds, use getFeed!!
     */
    FeedRegistryInterface public immutable feedRegistry; // 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf

    /**
     *
     */
    constructor(FeedRegistryInterface _feedRegistry) {
        feedRegistry = _feedRegistry;
    }

    //TODO should we add a compatability check to see if the base can convert to USD or ETH, and if the decimals are correct
    function getPricingInformation(address baseAsset) public view returns (uint256 price, uint256 timestamp) {
        try feedRegistry.latestRoundData(baseAsset, USD) returns (
            uint80,
            int256 price_,
            uint256,
            uint256 timestamp_,
            uint80
        ) {
            price = uint256(price_);
            timestamp = timestamp_;
        } catch {
            //if we can't find the USD price, then try the ETH price
            (, int256 price_, , uint256 timestamp_, ) = feedRegistry.latestRoundData(baseAsset, ETH);
            price = uint256(price_);
            timestamp = timestamp_;
            //now convert ETH to USD
            uint8 decimals = feedRegistry.decimals(baseAsset, ETH); //could assume that ETH is 18 decimals to remove external call
            uint256 ETHtoUSD = uint256(feedRegistry.latestAnswer(ETH, USD));
            price = (price * ETHtoUSD) / uint256(10**decimals);
            //latestTimestamp stays unchanged
        }
    }

    function getPriceWithDenomination(address baseAsset, address denomination)
        public
        view
        returns (uint256 price, uint256 timestamp)
    {
        (, int256 price_, , uint256 timestamp_, ) = feedRegistry.latestRoundData(baseAsset, denomination);
        price = uint256(price_);
        timestamp = timestamp_;
    }

    function getPriceRange(address baseAsset) public view returns (uint128 min, uint128 max) {
        try feedRegistry.getFeed(baseAsset, USD) returns (AggregatorV2V3Interface aggregator) {
            IChainlinkAggregator chainlinkAgg = IChainlinkAggregator(address(aggregator));
            min = uint128(uint192(chainlinkAgg.minAnswer()));
            max = uint128(uint192(chainlinkAgg.maxAnswer()));
        } catch {
            //if we can't find the USD price, then try the ETH price
            IChainlinkAggregator chainlinkAgg = IChainlinkAggregator(address(feedRegistry.getFeed(baseAsset, ETH)));
            min = uint128(uint192(chainlinkAgg.minAnswer()));
            max = uint128(uint192(chainlinkAgg.maxAnswer()));
            //now convert ETH to USD
            uint8 decimals = feedRegistry.decimals(baseAsset, ETH);
            uint128 ETHtoUSD = uint128(uint256(feedRegistry.latestAnswer(ETH, USD)));
            min = (min * ETHtoUSD) / uint128(10**decimals);
            max = (max * ETHtoUSD) / uint128(10**decimals);
        }
    }
}
