// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { FeedRegistryInterface } from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Sommelier Price Router
 * @notice Provides a universal interface allowing Sommelier contracts to retrieve secure pricing
 *         data from Chainlink.
 * @author crispymangoes, Brian Le
 */
contract PriceRouter is Ownable {
    using SafeTransferLib for ERC20;
    using SafeCast for int256;
    using Math for uint256;

    event AddAsset(address indexed asset);

    function multicall(bytes[] calldata data) external view returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionStaticCall(address(this), data[i]);
        }
        return results;
    }

    // =========================================== ASSETS CONFIG ===========================================

    /**
     * @param minPrice minimum price in USD for the asset before reverting
     * @param maxPrice maximum price in USD for the asset before reverting
     * @param isPriceRangeInETH if true price range values are given in ETH, if false price range is given in USD
     * @param heartbeat maximum allowed time that can pass with no update before price data is considered stale
     * @param isSupported whether this asset is supported by the platform or not
     */
    struct AssetConfig {
        uint256 minPrice;
        uint256 maxPrice;
        bool isPriceRangeInETH;
        uint96 heartbeat;
        bool isSupported;
    }

    /**
     * @notice Get the asset data for a given asset.
     */
    mapping(ERC20 => AssetConfig) public getAssetConfig;

    uint96 public constant DEFAULT_HEART_BEAT = 1 days;

    // ======================================= ADAPTOR OPERATIONS =======================================

    /**
     * @notice Attempted to set a minimum price below the Chainlink minimum price (with buffer).
     * @param minPrice minimum price attempted to set
     * @param bufferedMinPrice minimum price that can be set including buffer
     */
    error PriceRouter__InvalidMinPrice(uint256 minPrice, uint256 bufferedMinPrice);

    /**
     * @notice Attempted to set a maximum price above the Chainlink maximum price (with buffer).
     * @param maxPrice maximum price attempted to set
     * @param bufferedMaxPrice maximum price that can be set including buffer
     */
    error PriceRouter__InvalidMaxPrice(uint256 maxPrice, uint256 bufferedMaxPrice);

    /**
     * @notice Attempted to add an invalid asset.
     * @param asset address of the invalid asset
     */
    error PriceRouter__InvalidAsset(address asset);

    /**
     * @notice Attempted to add an asset with a certain price range denomination, but actual denomination was different.
     * @param expected price range denomination
     * @param actual price range denomination
     * @dev If an asset has price feeds in USD and ETH, the feed in USD is favored
     */
    error PriceRouter__PriceRangeDenominationMisMatch(bool expected, bool actual);

    /**
     * @notice Attempted to add an asset with invalid min/max prices.
     * @param min price
     * @param max price
     */
    error PriceRouter__MinPriceGreaterThanMaxPrice(uint256 min, uint256 max);

    /**
     * @notice Add an asset for the price router to support.
     * @param asset address of asset to support on the platform
     * @param minPrice minimum price in USD with 8 decimals for the asset before reverting,
     *                 set to `0` to use Chainlink's default
     * @param maxPrice maximum price in USD with 8 decimals for the asset before reverting,
     *                 set to `0` to use Chainlink's default
     * @param heartbeat maximum amount of time that can pass without the price data being updated
     *                  before reverting, set to `0` to use the default of 1 day
     */
    function addAsset(
        ERC20 asset,
        uint256 minPrice,
        uint256 maxPrice,
        bool rangeInETH,
        uint96 heartbeat
    ) external onlyOwner {
        if (address(asset) == address(0)) revert PriceRouter__InvalidAsset(address(asset));

        // Use Chainlink to get the min and max of the asset.
        ERC20 assetToQuery = _remap(asset);
        (uint256 minFromChainklink, uint256 maxFromChainlink, bool isETH) = _getPriceRange(assetToQuery);

        // Check if callers expected price range  denomination matches actual.
        if (rangeInETH != isETH) revert PriceRouter__PriceRangeDenominationMisMatch(rangeInETH, isETH);

        // Add a ~10% buffer to minimum and maximum price from Chainlink because Chainlink can stop updating
        // its price before/above the min/max price.
        uint256 bufferedMinPrice = minFromChainklink.mulWadDown(1.1e18);
        uint256 bufferedMaxPrice = maxFromChainlink.mulWadDown(0.9e18);

        if (minPrice == 0) {
            minPrice = bufferedMinPrice;
        } else {
            if (minPrice < bufferedMinPrice) revert PriceRouter__InvalidMinPrice(minPrice, bufferedMinPrice);
        }

        if (maxPrice == 0) {
            maxPrice = bufferedMaxPrice;
        } else {
            if (maxPrice > bufferedMaxPrice) revert PriceRouter__InvalidMaxPrice(maxPrice, bufferedMaxPrice);
        }

        if (minPrice >= maxPrice) revert PriceRouter__MinPriceGreaterThanMaxPrice(minPrice, maxPrice);

        getAssetConfig[asset] = AssetConfig({
            minPrice: minPrice,
            maxPrice: maxPrice,
            isPriceRangeInETH: isETH,
            heartbeat: heartbeat != 0 ? heartbeat : DEFAULT_HEART_BEAT,
            isSupported: true
        });

        emit AddAsset(address(asset));
    }

    function isSupported(ERC20 asset) external view returns (bool) {
        return getAssetConfig[asset].isSupported;
    }

    // ======================================= PRICING OPERATIONS =======================================

    /**
     * @notice Get the value of an asset in terms of another asset.
     * @param baseAsset address of the asset to get the price of in terms of the quote asset
     * @param amount amount of the base asset to price
     * @param quoteAsset address of the asset that the base asset is priced in terms of
     * @return value value of the amount of base assets specified in terms of the quote asset
     */
    function getValue(
        ERC20 baseAsset,
        uint256 amount,
        ERC20 quoteAsset
    ) external view returns (uint256 value) {
        value = amount.mulDivDown(getExchangeRate(baseAsset, quoteAsset), 10**baseAsset.decimals());
    }

    /**
     * @notice Attempted an operation with arrays of unequal lengths that were expected to be equal length.
     */
    error PriceRouter__LengthMismatch();

    /**
     * @notice Get the total value of multiple assets in terms of another asset.
     * @param baseAssets addresses of the assets to get the price of in terms of the quote asset
     * @param amounts amounts of each base asset to price
     * @param quoteAsset address of the assets that the base asset is priced in terms of
     * @return value total value of the amounts of each base assets specified in terms of the quote asset
     */
    function getValues(
        ERC20[] memory baseAssets,
        uint256[] memory amounts,
        ERC20 quoteAsset
    ) external view returns (uint256 value) {
        uint256 numOfAssets = baseAssets.length;
        if (numOfAssets != amounts.length) revert PriceRouter__LengthMismatch();

        uint8 quoteAssetDecimals = quoteAsset.decimals();

        for (uint256 i; i < numOfAssets; i++) {
            ERC20 baseAsset = baseAssets[i];

            value += amounts[i].mulDivDown(
                _getExchangeRate(baseAsset, quoteAsset, quoteAssetDecimals),
                10**baseAsset.decimals()
            );
        }
    }

    /**
     * @notice Get the exchange rate between two assets.
     * @param baseAsset address of the asset to get the exchange rate of in terms of the quote asset
     * @param quoteAsset address of the asset that the base asset is exchanged for
     * @return exchangeRate rate of exchange between the base asset and the quote asset
     */
    function getExchangeRate(ERC20 baseAsset, ERC20 quoteAsset) public view returns (uint256 exchangeRate) {
        exchangeRate = _getExchangeRate(baseAsset, quoteAsset, quoteAsset.decimals());
    }

    /**
     * @notice Get the exchange rates between multiple assets and another asset.
     * @param baseAssets addresses of the assets to get the exchange rates of in terms of the quote asset
     * @param quoteAsset address of the asset that the base assets are exchanged for
     * @return exchangeRates rate of exchange between the base assets and the quote asset
     */
    function getExchangeRates(ERC20[] memory baseAssets, ERC20 quoteAsset)
        external
        view
        returns (uint256[] memory exchangeRates)
    {
        uint8 quoteAssetDecimals = quoteAsset.decimals();

        uint256 numOfAssets = baseAssets.length;
        exchangeRates = new uint256[](numOfAssets);
        for (uint256 i; i < numOfAssets; i++)
            exchangeRates[i] = _getExchangeRate(baseAssets[i], quoteAsset, quoteAssetDecimals);
    }

    /**
     * @notice Get the minimum and maximum valid price for an asset.
     * @param asset address of the asset to get the price range of
     * @return min minimum valid price for the asset
     * @return max maximum valid price for the asset
     */
    function getPriceRange(ERC20 asset)
        public
        view
        returns (
            uint256 min,
            uint256 max,
            bool isETH
        )
    {
        AssetConfig memory config = getAssetConfig[asset];

        if (!config.isSupported) revert PriceRouter__UnsupportedAsset(address(asset));

        (min, max, isETH) = (config.minPrice, config.maxPrice, config.isPriceRangeInETH);
    }

    /**
     * @notice Get the minimum and maximum valid prices for an asset.
     * @param _assets addresses of the assets to get the price ranges for
     * @return min minimum valid price for each asset
     * @return max maximum valid price for each asset
     */
    function getPriceRanges(ERC20[] memory _assets)
        external
        view
        returns (
            uint256[] memory min,
            uint256[] memory max,
            bool[] memory isETH
        )
    {
        uint256 numOfAssets = _assets.length;
        (min, max, isETH) = (new uint256[](numOfAssets), new uint256[](numOfAssets), new bool[](numOfAssets));
        for (uint256 i; i < numOfAssets; i++) (min[i], max[i], isETH[i]) = getPriceRange(_assets[i]);
    }

    // =========================================== HELPER FUNCTIONS ===========================================

    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    function _remap(ERC20 asset) internal pure returns (ERC20) {
        if (asset == WETH) return ERC20(Denominations.ETH);
        if (asset == WBTC) return ERC20(Denominations.BTC);
        return asset;
    }

    /**
     * @notice Gets the exchange rate between a base and a quote asset
     * @param baseAsset the asset to convert into quoteAsset
     * @param quoteAsset the asset base asset is converted into
     * @return exchangeRate value of base asset in terms of quote asset
     */
    function _getExchangeRate(
        ERC20 baseAsset,
        ERC20 quoteAsset,
        uint8 quoteAssetDecimals
    ) internal view returns (uint256 exchangeRate) {
        exchangeRate = getValueInUSD(baseAsset).mulDivDown(10**quoteAssetDecimals, getValueInUSD(quoteAsset));
    }

    /**
     * @notice Attempted to update the asset to one that is not supported by the platform.
     * @param asset address of the unsupported asset
     */
    error PriceRouter__UnsupportedAsset(address asset);

    /**
     * @notice Attempted an operation to price an asset that under its minimum valid price.
     * @param asset address of the asset that is under its minimum valid price
     * @param price price of the asset
     * @param minPrice minimum valid price of the asset
     */
    error PriceRouter__AssetBelowMinPrice(address asset, uint256 price, uint256 minPrice);

    /**
     * @notice Attempted an operation to price an asset that under its maximum valid price.
     * @param asset address of the asset that is under its maximum valid price
     * @param price price of the asset
     * @param maxPrice maximum valid price of the asset
     */
    error PriceRouter__AssetAboveMaxPrice(address asset, uint256 price, uint256 maxPrice);

    /**
     * @notice Attempted to fetch a price for an asset that has not been updated in too long.
     * @param asset address of the asset thats price is stale
     * @param timeSinceLastUpdate seconds since the last price update
     * @param heartbeat maximum allowed time between price updates
     */
    error PriceRouter__StalePrice(address asset, uint256 timeSinceLastUpdate, uint256 heartbeat);

    // =========================================== CHAINLINK PRICING FUNCTIONS ===========================================\
    /**
     * @notice Feed Registry contract used to get chainlink data feeds, use getFeed!!
     */
    FeedRegistryInterface public constant feedRegistry =
        FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);

    /**
     * @notice Could not find an asset's price in USD or ETH.
     * @param asset address of the asset
     */
    error PriceRouter__PriceNotAvailable(address asset);

    /**
     * @notice Interacts with Chainlink feed registry and first tries to get `asset` price in USD,
     *         if that fails, then it tries to get `asset` price in ETH, and then converts the answer into USD.
     * @param asset the ERC20 token to get the price of.
     * @return price the price of `asset` in USD
     */
    function getValueInUSD(ERC20 asset) public view returns (uint256 price) {
        AssetConfig memory config = getAssetConfig[asset];

        // Make sure asset is supported.
        if (!config.isSupported) revert PriceRouter__UnsupportedAsset(address(asset));

        // Remap asset if need be.
        asset = _remap(asset);

        if (!config.isPriceRangeInETH) {
            // Price feed is in USD.
            (, int256 _price, , uint256 _timestamp, ) = feedRegistry.latestRoundData(address(asset), Denominations.USD);
            price = _price.toUint256();
            _checkPriceFeed(asset, price, _timestamp, config);
        } else {
            // Price feed is in ETH.
            (, int256 _price, , uint256 _timestamp, ) = feedRegistry.latestRoundData(address(asset), Denominations.ETH);
            price = _price.toUint256();
            _checkPriceFeed(asset, price, _timestamp, config);

            // Convert price from ETH to USD.
            price = _price.toUint256().mulWadDown(_getExchangeRateFromETHToUSD());
        }
    }

    /**
     * @notice Could not find an asset's price range in USD or ETH.
     * @param asset address of the asset
     */
    error PriceRouter__PriceRangeNotAvailable(address asset);

    /**
     * @notice Interacts with Chainlink feed registry and first tries to get `asset` price range in USD,
     *         if that fails, then it tries to get `asset` price range in ETH, and then converts the range into USD.
     * @param asset the ERC20 token to get the price range of.
     * @return min the minimum price where Chainlink nodes stop updating the oracle
     * @return max the maximum price where Chainlink nodes stop updating the oracle
     */
    function _getPriceRange(ERC20 asset)
        internal
        view
        returns (
            uint256 min,
            uint256 max,
            bool isETH
        )
    {
        try feedRegistry.getFeed(address(asset), Denominations.USD) returns (AggregatorV2V3Interface aggregator) {
            IChainlinkAggregator chainlinkAggregator = IChainlinkAggregator(address(aggregator));

            min = uint256(uint192(chainlinkAggregator.minAnswer()));
            max = uint256(uint192(chainlinkAggregator.maxAnswer()));
            isETH = false;
        } catch {
            // If we can't find the USD price, then try the ETH price.
            try feedRegistry.getFeed(address(asset), Denominations.ETH) returns (AggregatorV2V3Interface aggregator) {
                IChainlinkAggregator chainlinkAggregator = IChainlinkAggregator(address(aggregator));

                min = uint256(uint192(chainlinkAggregator.minAnswer()));
                max = uint256(uint192(chainlinkAggregator.maxAnswer()));
                isETH = true;
            } catch {
                revert PriceRouter__PriceRangeNotAvailable(address(asset));
            }
        }
    }

    /**
     * @notice helper function to grab pricing data for ETH in USD
     * @return exchangeRate the exchange rate for ETH in terms of USD
     * @dev It is inefficient to re-calculate _checkPriceFeed for ETH -> USD multiple times for a single TX,
     * but this is done in the explicit way because it is simpler and less prone to logic errors.
     */
    function _getExchangeRateFromETHToUSD() internal view returns (uint256 exchangeRate) {
        (, int256 _price, , uint256 _timestamp, ) = feedRegistry.latestRoundData(Denominations.ETH, Denominations.USD);
        exchangeRate = _price.toUint256();
        _checkPriceFeed(WETH, exchangeRate, _timestamp, getAssetConfig[WETH]);
    }

    /**
     * @notice helper function to validate a price feed is safe to use.
     * @param asset ERC20 asset price feed data is for.
     * @param value the price value the price feed gave.
     * @param timestamp the last timestamp the price feed was updated.
     * @param config the assets config storing min price, max price, and heartbeat requirements.
     */
    function _checkPriceFeed(
        ERC20 asset,
        uint256 value,
        uint256 timestamp,
        AssetConfig memory config
    ) internal view {
        uint256 minPrice = config.minPrice;
        if (value < minPrice) revert PriceRouter__AssetBelowMinPrice(address(asset), value, minPrice);

        uint256 maxPrice = config.maxPrice;
        if (value > maxPrice) revert PriceRouter__AssetAboveMaxPrice(address(asset), value, maxPrice);

        uint256 heartbeat = config.heartbeat;
        uint256 timeSinceLastUpdate = block.timestamp - timestamp;
        if (timeSinceLastUpdate > heartbeat)
            revert PriceRouter__StalePrice(address(asset), timeSinceLastUpdate, heartbeat);
    }
}
