// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ICurvePool } from "src/interfaces/external/ICurvePool.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { console } from "@forge-std/Test.sol";

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
    using Address for address;

    event AddAsset(address indexed asset);

    //TODO could probs just replace this with a function that does two get values, and subtracts them.
    function multicall(bytes[] calldata data) external view returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionStaticCall(address(this), data[i]);
        }
        return results;
    }

    // =========================================== ASSETS CONFIG ===========================================
    /**
     * @notice Stores bare minimum settings all derivatives support like so.
     * 256 Bit
     * uint88 Reserved for future use.
     * uint160 Source address: Where does this contract look to handle pricing.
     * uint8 Derivative: Note 0 is an invalid Derivative.
     * 0 Bit
     */

    struct AssetSettings {
        uint8 derivative;
        address source;
    }

    mapping(ERC20 => AssetSettings) public getAssetSettings; // maps an asset -> settings

    uint24 public constant DEFAULT_HEART_BEAT = 1 days;

    uint8 public constant USD_DECIMALS = 8;

    uint8 public constant ETH_DECIMALS = 18;

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

    error PriceRouter__BadAnswer(uint256 answer, uint256 expectedAnswer);

    /**
     * @notice Attempted to add an asset with invalid min/max prices.
     * @param min price
     * @param max price
     */
    error PriceRouter__MinPriceGreaterThanMaxPrice(uint256 min, uint256 max);

    uint256 public constant EXPECTED_ANSWER_DEVIATION = 0.02e18;

    // Struct to store pricing information during calls.
    struct PriceCache {
        address asset;
        uint96 price;
    }

    // The size of the price cache. A larger cache can hold more values, but incurs a larger gas cost overhead.
    // A smaller cache has a smaller gas overhead but caches less prices.
    uint8 private constant PRICE_CACHE_SIZE = 8;

    function addAsset(
        ERC20 _asset,
        AssetSettings memory _settings,
        bytes memory _storage,
        uint256 _expectedAnswer
    ) external onlyOwner {
        if (address(_asset) == address(0)) revert PriceRouter__InvalidAsset(address(_asset));
        if (_settings.derivative == 0) revert("Invalid Derivative");
        if (_settings.derivative == 1) {
            _setupPriceForChainlinkDerivative(_asset, _settings.source, _storage);
        } else if (_settings.derivative == 2) {
            _setupPriceForCurveDerivative(_asset, _settings.source, _storage);
        }

        getAssetSettings[_asset] = _settings;

        uint256 minAnswer = _expectedAnswer.mulWadDown((1e18 - EXPECTED_ANSWER_DEVIATION));
        uint256 maxAnswer = _expectedAnswer.mulWadDown((1e18 + EXPECTED_ANSWER_DEVIATION));

        // Create an empty Price Cache.
        PriceCache[PRICE_CACHE_SIZE] memory cache;
        // Not a view function so pass in false for `isView`.
        uint256 answer = _getPriceInUSD(_asset, _settings, cache);

        if (answer < minAnswer || answer > maxAnswer) revert PriceRouter__BadAnswer(answer, _expectedAnswer);

        emit AddAsset(address(_asset));
    }

    /**
     * @notice return bool indicating whether or not an asset has been set up.
     * @dev Since `addAsset` enforces the derivative is non zero, checking if the stored setting
     *      is nonzero is sufficient to see if the asset is set up.
     */
    function isSupported(ERC20 asset) external view returns (bool) {
        return getAssetSettings[asset].derivative > 0;
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
        ERC20[] calldata baseAssets,
        uint256[] calldata amounts,
        ERC20 quoteAsset
    ) external view returns (uint256) {
        // Create an empty Price Cache.
        PriceCache[PRICE_CACHE_SIZE] memory cache;

        if (baseAssets.length != amounts.length) revert PriceRouter__LengthMismatch();
        uint256 quotePrice;
        {
            AssetSettings memory quoteSettings = getAssetSettings[quoteAsset];
            if (quoteSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(quoteAsset));
            quotePrice = _getPriceInUSD(quoteAsset, quoteSettings, cache);
        }
        uint256 valueInQuote;
        uint256 price;
        uint8 quoteDecimals = quoteAsset.decimals();

        for (uint8 i = 0; i < baseAssets.length; i++) {
            // Skip zero amount values.
            if (amounts[i] == 0) continue;
            ERC20 baseAsset = baseAssets[i];
            if (baseAsset == quoteAsset) valueInQuote += amounts[i];
            else {
                AssetSettings memory baseSettings = getAssetSettings[baseAsset];
                if (baseSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(baseAsset));
                price = _getPriceInUSD(baseAsset, baseSettings, cache);
                uint256 valueInUSD = (amounts[i].mulDivDown(price, 10**baseAsset.decimals()));
                valueInQuote += valueInUSD.mulDivDown(10**quoteDecimals, quotePrice);
            }
        }
        return valueInQuote;
    }

    /**
     * @notice Get the exchange rate between two assets.
     * @param baseAsset address of the asset to get the exchange rate of in terms of the quote asset
     * @param quoteAsset address of the asset that the base asset is exchanged for
     * @return exchangeRate rate of exchange between the base asset and the quote asset
     */
    function getExchangeRate(ERC20 baseAsset, ERC20 quoteAsset) public view returns (uint256 exchangeRate) {
        AssetSettings memory baseSettings = getAssetSettings[baseAsset];
        AssetSettings memory quoteSettings = getAssetSettings[quoteAsset];
        if (baseSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(baseAsset));
        if (quoteSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(quoteAsset));

        // Create an empty Price Cache.
        PriceCache[PRICE_CACHE_SIZE] memory cache;
        // Pass in zero for ethToUsd, since it has not been set yet.
        exchangeRate = _getExchangeRate(
            baseAsset,
            baseSettings,
            quoteAsset,
            quoteSettings,
            quoteAsset.decimals(),
            cache
        );
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
        AssetSettings memory quoteSettings = getAssetSettings[quoteAsset];
        if (quoteSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(quoteAsset));

        // Create an empty Price Cache.
        PriceCache[PRICE_CACHE_SIZE] memory cache;

        uint256 numOfAssets = baseAssets.length;
        exchangeRates = new uint256[](numOfAssets);
        for (uint256 i; i < numOfAssets; i++) {
            AssetSettings memory baseSettings = getAssetSettings[baseAssets[i]];
            if (baseSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(baseAssets[i]));
            exchangeRates[i] = _getExchangeRate(
                baseAssets[i],
                baseSettings,
                quoteAsset,
                quoteSettings,
                quoteAssetDecimals,
                cache
            );
        }
    }

    // =========================================== HELPER FUNCTIONS ===========================================

    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /**
     * @notice Attempted to update the asset to one that is not supported by the platform.
     * @param asset address of the unsupported asset
     */
    error PriceRouter__UnsupportedAsset(address asset);

    /**
     * @notice Gets the exchange rate between a base and a quote asset
     * @param baseAsset the asset to convert into quoteAsset
     * @param quoteAsset the asset base asset is converted into
     * @return exchangeRate value of base asset in terms of quote asset
     */
    function _getExchangeRate(
        ERC20 baseAsset,
        AssetSettings memory baseSettings,
        ERC20 quoteAsset,
        AssetSettings memory quoteSettings,
        uint8 quoteAssetDecimals,
        PriceCache[PRICE_CACHE_SIZE] memory cache
    ) internal view returns (uint256) {
        uint256 basePrice;
        uint256 quotePrice;
        basePrice = _getPriceInUSD(baseAsset, baseSettings, cache);
        quotePrice = _getPriceInUSD(quoteAsset, quoteSettings, cache);
        uint256 exchangeRate = basePrice.mulDivDown(10**quoteAssetDecimals, quotePrice);
        return exchangeRate;
    }

    function _getPriceInUSD(
        ERC20 asset,
        AssetSettings memory settings,
        PriceCache[PRICE_CACHE_SIZE] memory cache
    ) internal view returns (uint256) {
        uint8 lastIndex = PRICE_CACHE_SIZE;
        for (uint8 i; i < PRICE_CACHE_SIZE; ++i) {
            // Did not find our price in the cache.
            if (cache[i].asset == address(0)) {
                lastIndex = i;
                break;
            }
            // Did find our price in the cache.
            if (cache[i].asset == address(asset)) {
                // console.log("Price Found", cache[i].asset);
                return cache[i].price;
            }
        }
        uint256 exchangeRate;
        if (settings.derivative == 1) {
            exchangeRate = _getPriceForChainlinkDerivative(asset, settings.source, cache);
        } else if (settings.derivative == 2) {
            exchangeRate = _getPriceForCurveDerivative(asset, settings.source, cache);
        }

        // If there is room in the cache, the price fits in a uint96, then find the next spot available.
        if (lastIndex < PRICE_CACHE_SIZE && exchangeRate <= type(uint96).max) {
            for (uint8 i = lastIndex; i < PRICE_CACHE_SIZE; ++i) {
                // Price is not in the cache, and there is room to store it.
                if (cache[i].asset == address(0)) {
                    cache[i] = PriceCache(address(asset), uint96(exchangeRate));
                    break;
                }
            }
        }

        // console.log("------------- CACHE -------------");
        // console.log("Asset", cache[0].asset);
        // console.log("Price", cache[0].price);
        // console.log("Asset", cache[1].asset);
        // console.log("Price", cache[1].price);
        // console.log("Asset", cache[2].asset);
        // console.log("Price", cache[2].price);
        // console.log("Asset", cache[3].asset);
        // console.log("Price", cache[3].price);
        // console.log("Asset", cache[4].asset);
        // console.log("Price", cache[4].price);
        // console.log("Asset", cache[5].asset);
        // console.log("Price", cache[5].price);
        // console.log("Asset", cache[6].asset);
        // console.log("Price", cache[6].price);
        // console.log("Asset", cache[7].asset);
        // console.log("Price", cache[7].price);
        // console.log("----------- END CACHE -----------");

        return exchangeRate;
    }

    // =========================================== CHAINLINK PRICE DERIVATIVE ===========================================\
    struct ChainlinkDerivativeStorage {
        uint144 max;
        uint80 min;
        uint24 heartbeat;
        bool inETH;
    }
    /**
     * @notice Chainlink Derivative Storage
     */
    mapping(ERC20 => ChainlinkDerivativeStorage) public getChainlinkDerivativeStorage;

    function _setupPriceForChainlinkDerivative(
        ERC20 _asset,
        address _source,
        bytes memory _storage
    ) internal {
        ChainlinkDerivativeStorage memory parameters = abi.decode(_storage, (ChainlinkDerivativeStorage));

        // Use Chainlink to get the min and max of the asset.
        IChainlinkAggregator aggregator = IChainlinkAggregator(IChainlinkAggregator(_source).aggregator());
        uint256 minFromChainklink = uint256(uint192(aggregator.minAnswer()));
        uint256 maxFromChainlink = uint256(uint192(aggregator.maxAnswer()));

        // Add a ~10% buffer to minimum and maximum price from Chainlink because Chainlink can stop updating
        // its price before/above the min/max price.
        uint256 bufferedMinPrice = (minFromChainklink * 1.1e18) / 1e18;
        uint256 bufferedMaxPrice = (maxFromChainlink * 0.9e18) / 1e18;

        if (parameters.min == 0) {
            // Revert if bufferedMinPrice overflows because uint80 is too small to hold the minimum price,
            // and lowering it to uint80 is not safe because the price feed can stop being updated before
            // it actually gets to that lower price.
            if (bufferedMinPrice > type(uint80).max) revert("Buffered Min Overflow");
            parameters.min = uint80(bufferedMinPrice);
        } else {
            if (parameters.min < bufferedMinPrice)
                revert PriceRouter__InvalidMinPrice(parameters.min, bufferedMinPrice);
        }

        if (parameters.max == 0) {
            //Do not revert even if bufferedMaxPrice is greater than uint144, because lowering it to uint144 max is more conservative.
            parameters.max = bufferedMaxPrice > type(uint144).max ? type(uint144).max : uint144(bufferedMaxPrice);
        } else {
            if (parameters.max > bufferedMaxPrice)
                revert PriceRouter__InvalidMaxPrice(parameters.max, bufferedMaxPrice);
        }

        if (parameters.min >= parameters.max)
            revert PriceRouter__MinPriceGreaterThanMaxPrice(parameters.min, parameters.max);

        parameters.heartbeat = parameters.heartbeat != 0 ? parameters.heartbeat : DEFAULT_HEART_BEAT;

        getChainlinkDerivativeStorage[_asset] = parameters;
    }

    function _getPriceForChainlinkDerivative(
        ERC20 _asset,
        address _source,
        PriceCache[PRICE_CACHE_SIZE] memory cache
    ) internal view returns (uint256) {
        ChainlinkDerivativeStorage memory parameters = getChainlinkDerivativeStorage[_asset];
        IChainlinkAggregator aggregator = IChainlinkAggregator(_source);
        (, int256 _price, , uint256 _timestamp, ) = aggregator.latestRoundData();
        uint256 price = _price.toUint256();
        _checkPriceFeed(address(_asset), price, _timestamp, parameters.max, parameters.min, parameters.heartbeat);
        // If price is in ETH, then convert price into USD.
        if (parameters.inETH) {
            uint256 _ethToUsd = _getPriceInUSD(WETH, getAssetSettings[WETH], cache);
            price = price.mulWadDown(_ethToUsd);
        }
        return price;
    }

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

    /**
     * @notice helper function to validate a price feed is safe to use.
     * @param asset ERC20 asset price feed data is for.
     * @param value the price value the price feed gave.
     * @param timestamp the last timestamp the price feed was updated.
     */
    //TODO natspec
    function _checkPriceFeed(
        address asset,
        uint256 value,
        uint256 timestamp,
        uint144 max,
        uint88 min,
        uint24 heartbeat
    ) internal view {
        if (value < min) revert PriceRouter__AssetBelowMinPrice(address(asset), value, min);

        if (value > max) revert PriceRouter__AssetAboveMaxPrice(address(asset), value, max);

        uint256 timeSinceLastUpdate = block.timestamp - timestamp;
        if (timeSinceLastUpdate > heartbeat)
            revert PriceRouter__StalePrice(address(asset), timeSinceLastUpdate, heartbeat);
    }

    // =========================================== CURVE PRICE DERIVATIVE ===========================================
    /**
     * @notice Stores set of Curve Assets that are suseptible to reentrancy attacks.
     */
    mapping(address => bool) curveReentrancyAssets;

    function addAssetToCurveReentrancySet(address asset) external onlyOwner {
        curveReentrancyAssets[asset] = true;
    }

    /**
     * @notice Curve Derivative Storage
     */
    mapping(ERC20 => address[]) public getCurveDerivativeStorage;

    // source is the pool
    function _setupPriceForCurveDerivative(
        ERC20 _asset,
        address _source,
        bytes memory
    ) internal {
        // Could use _storage and do a check?
        ICurvePool pool = ICurvePool(_source);
        uint8 coinsLength = 0;
        while (true) {
            try pool.coins(coinsLength) {
                coinsLength++;
            } catch {
                break;
            }
        }
        address[] memory coins = new address[](coinsLength);
        for (uint256 i = 0; i < coinsLength; i++) {
            coins[i] = pool.coins(i);
        }

        getCurveDerivativeStorage[_asset] = coins;
    }

    //TODO this assumes Curve pools NEVER add or remove tokens
    function _getPriceForCurveDerivative(
        ERC20 asset,
        address _source,
        PriceCache[PRICE_CACHE_SIZE] memory cache
    ) internal view returns (uint256 price) {
        ICurvePool pool = ICurvePool(_source);

        address[] memory coins = getCurveDerivativeStorage[asset];

        uint256 minPrice = type(uint256).max;
        for (uint256 i = 0; i < coins.length; i++) {
            ERC20 poolAsset = ERC20(coins[i]);
            uint256 tokenPrice = _getPriceInUSD(poolAsset, getAssetSettings[poolAsset], cache);
            if (tokenPrice < minPrice) minPrice = tokenPrice;
        }

        if (minPrice == type(uint256).max) revert("Min price not found.");

        // Virtual price is based off the Curve Token decimals.
        uint256 curveTokenDecimals = ERC20(asset).decimals();
        price = minPrice.mulDivDown(pool.get_virtual_price(), 10**curveTokenDecimals);
    }
}
