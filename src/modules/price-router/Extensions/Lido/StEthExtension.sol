// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

interface CurveNgPool {
    function ema_price() external view returns (uint256);
}

/**
 * @title Sommelier Price Router stEth Extension
 * @notice Allows the Price Router to price stEth in a less volatile way,
 *         without assuming a 1:1 peg.
 * @author crispymangoes
 */
contract StEthExtension is Extension {
    using Math for uint256;

    /**
     * @notice The bps the curve and chainlink answer can differ by, and still use the curve answer.
     * @dev If curve and chainlink answers differ by more than this, chainlink is used by default.
     */
    uint256 public immutable allowedDivergence;

    /**
     * @notice Current networks stETH - ETH ng pool.
     */
    CurveNgPool public immutable curveStEthWethNgPool;

    /**
     * @notice Current networks stETH to ETH data feed.
     */
    IChainlinkAggregator public immutable stEthToEthDataFeed;

    /**
     * @notice Heartbeat to use for datafeed.
     */
    uint24 public immutable chainlinkHeartbeat;

    /**
     * @notice Current networks WETH address.
     */
    ERC20 public immutable WETH;

    /**
     * @notice Current networks stETH address.
     */
    address public immutable stETH;

    constructor(
        PriceRouter _priceRouter,
        uint256 _allowedDivergence,
        address _curveStEthWethNgPool,
        address _stEthToEthDataFeed,
        uint24 _heartbeat,
        address _weth,
        address _steth
    ) Extension(_priceRouter) {
        allowedDivergence = _allowedDivergence;

        curveStEthWethNgPool = CurveNgPool(_curveStEthWethNgPool);
        stEthToEthDataFeed = IChainlinkAggregator(_stEthToEthDataFeed);
        chainlinkHeartbeat = _heartbeat;
        WETH = ERC20(_weth);
        stETH = _steth;
    }

    /**
     * @notice Attempted to use this extension to price something other than stEth.
     */
    error StEthExtension__ASSET_NOT_STETH();

    /**
     * @notice Attempted to fetch a price for an asset that has not been updated in too long.
     * @param timeSinceLastUpdate seconds since the last price update
     * @param heartbeat maximum allowed time between price updates
     */
    error StEthExtension__StalePrice(uint256 timeSinceLastUpdate, uint256 heartbeat);

    /**
     * @notice Queried price was 0 or negative.
     */
    error StEthExtension__ZeroOrNegativePrice();

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset stEth
     * @dev bytes input is not used
     */
    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        if (address(asset) != stETH) revert StEthExtension__ASSET_NOT_STETH();
        // Make sure we can get prices from above sources
        _getAnswerFromChainlink();
        _getAnswerFromCurve();
    }

    /**
     * @notice Called during pricing operations.
     * @dev asset not used since setup function confirms `asset` is stEth.
     */
    function getPriceInUSD(ERC20) external view override returns (uint256) {
        // Get Chainlink stETH - ETH price.
        uint256 chainlinkAnswer = _getAnswerFromChainlink();
        // Get price from Curve EMA.
        uint256 curveAnswer = _getAnswerFromCurve();

        // Get ETH to USD exchange rate from price router.
        uint256 exchangeRate = priceRouter.getPriceInUSD(WETH);

        uint256 answerToUse;

        // Compare the two, if they are within allowed divergence, use curve ema, otherwise use chainlink value.
        if (curveAnswer > chainlinkAnswer) {
            if (chainlinkAnswer.mulDivDown(1e4 + allowedDivergence, 1e4) < curveAnswer) answerToUse = chainlinkAnswer;
            else answerToUse = curveAnswer;
        } else {
            if (chainlinkAnswer.mulDivDown(1e4 - allowedDivergence, 1e4) > curveAnswer) answerToUse = chainlinkAnswer;
            else answerToUse = curveAnswer;
        }

        // Cap answer at a 1:1 peg.
        if (answerToUse > 1e18) answerToUse = 1e18;
        return answerToUse.mulDivDown(exchangeRate, 1e18);
    }

    /**
     * @notice Get Chainlink Answer, validating price and timestamp are reasonable.
     */
    function _getAnswerFromChainlink() internal view returns (uint256) {
        (, int256 _price, , uint256 _timestamp, ) = stEthToEthDataFeed.latestRoundData();
        uint256 timeSinceLastUpdate = block.timestamp - _timestamp;
        if (timeSinceLastUpdate > chainlinkHeartbeat)
            revert StEthExtension__StalePrice(timeSinceLastUpdate, chainlinkHeartbeat);
        if (_price <= 0) revert StEthExtension__ZeroOrNegativePrice();

        return uint256(_price);
    }

    /**
     * @notice Get Curve Answer, validating price is reasonable.
     */
    function _getAnswerFromCurve() internal view returns (uint256) {
        uint256 price = curveStEthWethNgPool.ema_price();
        if (price <= 0) revert StEthExtension__ZeroOrNegativePrice();

        return price;
    }
}
