// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { BaseAdaptor } from "./BaseAdaptor.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { OracleRouter } from "./OracleRouter.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "./interfaces/IChainlinkAggregator.sol";

//TODO when converting int's to uint's does V8 check if the value is negative, or if its too large to fit into 128 bits?
//TODO does this even make sense to have a base adaptor? What functionality would all the adaptors share?
contract ChainlinkPriceFeedAdaptor {
    address public constant USD = address(840); //used by feed registry to denominate USD
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant BTC = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

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

    //TODO make this smarter, if it can't find the USD price, then try finding the ETH price and converting into USD
    //TODO should this revert if it can't find USD or ETH price?
    function getPricingInformation(address baseAsset)
        external
        view
        returns (OracleRouter.PricingInformation memory info)
    {
        //convert wrapped addresses to unwrapped
        baseAsset = baseAsset == WETH ? ETH : baseAsset;
        baseAsset = baseAsset == WBTC ? BTC : baseAsset;
        try feedRegistry.getFeed(baseAsset, USD) returns (AggregatorV2V3Interface aggregator) {
            IChainlinkAggregator chainlinkAgg = IChainlinkAggregator(address(aggregator));
            info = OracleRouter.PricingInformation({
                minPrice: uint256(uint192(chainlinkAgg.minAnswer())), //throws error if trying to convert from a int256 directly to a uint256
                maxPrice: uint256(uint192(chainlinkAgg.maxAnswer())),
                price: uint256(uint256(feedRegistry.latestAnswer(baseAsset, USD))), // Raises No Access revert if you try to get this directly from the aggregator
                lastTimestamp: uint256(feedRegistry.latestTimestamp(baseAsset, USD))
            });
        } catch {
            //if we can't find the USD price, then try the ETH price
            IChainlinkAggregator chainlinkAgg = IChainlinkAggregator(address(feedRegistry.getFeed(baseAsset, ETH)));
            info = OracleRouter.PricingInformation({
                minPrice: uint256(uint192(chainlinkAgg.minAnswer())), //throws error if trying to convert from a int256 directly to a uint256
                maxPrice: uint256(uint192(chainlinkAgg.maxAnswer())),
                price: uint256(feedRegistry.latestAnswer(baseAsset, ETH)), // Raises No Access revert if you try to get this directly from the aggregator
                lastTimestamp: uint256(feedRegistry.latestTimestamp(baseAsset, ETH))
            });
            //now convert ETH to USD
            uint8 decimals = feedRegistry.decimals(baseAsset, ETH);
            uint256 ETHtoUSD = uint256(uint256(feedRegistry.latestAnswer(ETH, USD)));
            info.minPrice = (info.minPrice * ETHtoUSD) / uint256(10**decimals);
            info.maxPrice = (info.maxPrice * ETHtoUSD) / uint256(10**decimals);
            info.price = (info.price * ETHtoUSD) / uint256(10**decimals);
            //latestTimestamp stays unchanged
        }
    }
}
