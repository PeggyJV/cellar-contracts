// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { UniswapV3Pool } from "src/interfaces/external/UniswapV3Pool.sol";
import { OracleLibrary } from "@uniswapV3P/libraries/OracleLibrary.sol";
import { ISTETH } from "src/interfaces/external/ISTETH.sol";

/**
 * @title Sommelier Price Router stEth Extension
 * @notice Allows the Price Router to price stEth in a less volatile way,
 *         without assuming a 1:1 peg.
 * @author crispymangoes
 */
contract StEthExtension is Extension {
    using Math for uint256;

    /**
     * @notice Provided secondsAgo does not meet minimum,
     */
    error StEthExtension__SecondsAgoDoesNotMeetMinimum();

    /**
     * @notice The smallest possible TWAP that can be used.
     */
    uint32 public constant MINIMUM_SECONDS_AGO = 900;

    /**
     * @notice The bps the uniswap and chainlink answer can differ by, and still use the uniswap answer.
     * @dev If uniswap and chainlink answers differ by more than this, chainlink is used by default.
     */
    uint256 public immutable allowedDivergence;

    /**
     * @notice Current networks wsteth - ETH Uniswap V3 pool.
     */
    UniswapV3Pool public immutable uniV3WstEthWethPool;

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
     * @notice Ethereum mainnet stEth.
     */
    ISTETH public immutable stEth;

    /**
     * @notice Twap Duration.
     */
    uint32 public immutable twapDuration;

    /**
     * @notice The minimum harmonic mean liquidity that must be present in a TWAP observation.
     */
    uint128 public immutable minimumMeanLiquidity;

    constructor(
        PriceRouter _priceRouter,
        uint256 _allowedDivergence,
        address _uniV3WstEthWethPool,
        address _stEthToEthDataFeed,
        uint24 _heartbeat,
        address _weth,
        address _steth,
        uint32 _twapDuration,
        uint128 _minimumMeanLiquidity
    ) Extension(_priceRouter) {
        allowedDivergence = _allowedDivergence;

        uniV3WstEthWethPool = UniswapV3Pool(_uniV3WstEthWethPool);
        stEthToEthDataFeed = IChainlinkAggregator(_stEthToEthDataFeed);
        chainlinkHeartbeat = _heartbeat;
        WETH = ERC20(_weth);
        stEth = ISTETH(_steth);
        if (_twapDuration < MINIMUM_SECONDS_AGO) revert StEthExtension__SecondsAgoDoesNotMeetMinimum();
        twapDuration = _twapDuration;
        minimumMeanLiquidity = _minimumMeanLiquidity;
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
        if (address(asset) != address(stEth)) revert StEthExtension__ASSET_NOT_STETH();
        // Make sure we can get prices from above sources.
        getAnswerFromChainlink();
        getAnswerFromUniswap();
    }

    /**
     * @notice Called during pricing operations.
     * @dev asset not used since setup function confirms `asset` is stEth.
     */
    function getPriceInUSD(ERC20) external view override returns (uint256) {
        // Get Chainlink stETH - ETH price.
        uint256 chainlinkAnswer = getAnswerFromChainlink();
        // Get price from Uniswap V3.
        uint256 uniswapAnswer = getAnswerFromUniswap();

        // Get ETH to USD exchange rate from price router.
        uint256 exchangeRate = priceRouter.getPriceInUSD(WETH);

        uint256 answerToUse;

        // Compare the two, if they are within allowed divergence, use uniswap twap, otherwise use chainlink value.
        if (uniswapAnswer > 0) {
            if (uniswapAnswer > chainlinkAnswer) {
                if (chainlinkAnswer.mulDivDown(1e4 + allowedDivergence, 1e4) < uniswapAnswer)
                    answerToUse = chainlinkAnswer;
                else answerToUse = uniswapAnswer;
            } else {
                if (chainlinkAnswer.mulDivDown(1e4 - allowedDivergence, 1e4) > uniswapAnswer)
                    answerToUse = chainlinkAnswer;
                else answerToUse = uniswapAnswer;
            }
        } else answerToUse = chainlinkAnswer;

        // Cap answer at a 1:1 peg.
        if (answerToUse > 1e18) answerToUse = 1e18;
        return answerToUse.mulDivDown(exchangeRate, 1e18);
    }

    /**
     * @notice Get Chainlink Answer, validating price and timestamp are reasonable.
     */
    function getAnswerFromChainlink() public view returns (uint256) {
        (, int256 _price, , uint256 _timestamp, ) = stEthToEthDataFeed.latestRoundData();
        uint256 timeSinceLastUpdate = block.timestamp - _timestamp;
        if (timeSinceLastUpdate > chainlinkHeartbeat)
            revert StEthExtension__StalePrice(timeSinceLastUpdate, chainlinkHeartbeat);
        if (_price <= 0) revert StEthExtension__ZeroOrNegativePrice();

        return uint256(_price);
    }

    /**
     * @notice Get Uniswap answer, validating price is reasonable.
     * @dev Below call to `consult` would revert with error "OLD" if oldest observation is not old enough, but in this case,
     *      we do not want to revert, instead we want to default to use the Chainlink Answer.
     */
    function getAnswerFromUniswap() public view returns (uint256) {
        uint32 oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(address(uniV3WstEthWethPool));
        // If oldest observation will not work for TWAP, return 0, so we use chainlink answer.
        if (oldestObservation < twapDuration) return 0;

        (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity) = OracleLibrary.consult(
            address(uniV3WstEthWethPool),
            twapDuration
        );
        // Get the amount of quote token each base token is worth.
        uint256 answer = OracleLibrary.getQuoteAtTick(arithmeticMeanTick, uint128(1e18), address(stEth), address(WETH));

        // If mean liquidity during observation is less than minimumMeanLiquidity, return 0, so we use chainlink answer.
        if (harmonicMeanLiquidity < minimumMeanLiquidity) return 0;

        // Convert answer to be in terms of stEth.
        answer = answer.mulDivDown(1e18, stEth.getPooledEthByShares(1e18));
        return answer;
    }
}
