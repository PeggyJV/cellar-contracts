// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20, SafeTransferLib } from "src/base/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ICurvePool } from "src/interfaces/external/ICurvePool.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

/**
 * @title Sommelier Price Router
 * @notice Provides a universal interface allowing Sommelier contracts to retrieve secure pricing
 *         data from Chainlink.
 * @author crispymangoes, Brian Le
 */
contract PriceRouter is Ownable, AutomationCompatibleInterface {
    using SafeTransferLib for ERC20;
    using SafeCast for int256;
    using Math for uint256;
    using Address for address;

    event AddAsset(address indexed asset);

    // =========================================== ASSETS CONFIG ===========================================
    /**
     * @notice Bare minimum settings all derivatives support.
     * @param derivative the derivative used to price the asset
     * @param source the address used to price the asset
     */
    struct AssetSettings {
        uint8 derivative;
        address source;
    }

    /**
     * @notice Mapping between an asset to price and its `AssetSettings`.
     */
    mapping(ERC20 => AssetSettings) public getAssetSettings;

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
     * @notice Attempted to add an asset, but actual answer was outside range of expectedAnswer.
     */
    error PriceRouter__BadAnswer(uint256 answer, uint256 expectedAnswer);

    /**
     * @notice Attempted to perform an operation using an unkown derivative.
     */
    error PriceRouter__UnkownDerivative(uint8 unkownDerivative);

    /**
     * @notice Attempted to add an asset with invalid min/max prices.
     * @param min price
     * @param max price
     */
    error PriceRouter__MinPriceGreaterThanMaxPrice(uint256 min, uint256 max);

    /**
     * @notice The allowed deviation between the expected answer vs the actual answer.
     */
    uint256 public constant EXPECTED_ANSWER_DEVIATION = 0.02e18;

    /**
     * @notice Stores pricing information during calls.
     * @param asset the address of the asset
     * @param price the USD price of the asset
     * @dev If the price does not fit into a uint96, the asset is NOT added to the cache.
     */
    struct PriceCache {
        address asset;
        uint96 price;
    }

    /**
     * @notice The size of the price cache. A larger cache can hold more values,
     *         but incurs a larger gas cost overhead. A smaller cache has a
     *         smaller gas overhead but caches less prices.
     */
    uint8 private constant PRICE_CACHE_SIZE = 8;

    /**
     * @notice Allows owner to add assets to the price router.
     * @dev Performs a sanity check by comparing the price router computed price to
     * a user input `_expectedAnswer`.
     * @param _asset the asset to add to the pricing router
     * @param _settings the settings for `_asset`
     *        @dev The `derivative` value in settings MUST be non zero.
     * @param _storage arbitrary bytes data used to configure `_asset` pricing
     * @param _expectedAnswer the expected answer for the asset from  `_getPriceInUSD`
     */
    function addAsset(
        ERC20 _asset,
        AssetSettings memory _settings,
        bytes memory _storage,
        uint256 _expectedAnswer
    ) external onlyOwner {
        if (address(_asset) == address(0)) revert PriceRouter__InvalidAsset(address(_asset));
        // Zero is an invalid derivative.
        if (_settings.derivative == 0) revert PriceRouter__UnkownDerivative(_settings.derivative);

        // Call setup function for appropriate derivative.
        if (_settings.derivative == 1) {
            _setupPriceForChainlinkDerivative(_asset, _settings.source, _storage);
        } else if (_settings.derivative == 2) {
            _setupPriceForCurveDerivative(_asset, _settings.source, _storage);
        } else if (_settings.derivative == 3) {
            _setupPriceForCurveV2Derivative(_asset, _settings.source, _storage);
        } else if (_settings.derivative == 4) {
            _setupPriceForAaveDerivative(_asset, _settings.source, _storage);
        } else revert PriceRouter__UnkownDerivative(_settings.derivative);

        // Check `_getPriceInUSD` against `_expectedAnswer`.
        uint256 minAnswer = _expectedAnswer.mulWadDown((1e18 - EXPECTED_ANSWER_DEVIATION));
        uint256 maxAnswer = _expectedAnswer.mulWadDown((1e18 + EXPECTED_ANSWER_DEVIATION));
        // Create an empty Price Cache.
        PriceCache[PRICE_CACHE_SIZE] memory cache;
        getAssetSettings[_asset] = _settings;
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

    // ======================================= CHAINLINK AUTOMATION =======================================
    /**
     * @notice `checkUpkeep` is set up to allow for multiple derivatives to use Chainlink Automation.
     */
    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData) {
        (uint8 derivative, bytes memory derivativeCheckData) = abi.decode(checkData, (uint8, bytes));

        if (derivative == 2) {
            (upkeepNeeded, performData) = _checkVirtualPriceBound(derivativeCheckData);
        } else if (derivative == 3) {
            (upkeepNeeded, performData) = _checkVirtualPriceBound(derivativeCheckData);
        } else revert PriceRouter__UnkownDerivative(derivative);
    }

    /**
     * @notice `performUpkeep` is set up to allow for multiple derivatives to use Chainlink Automation.
     */
    function performUpkeep(bytes calldata performData) external {
        (uint8 derivative, bytes memory derivativePerformData) = abi.decode(performData, (uint8, bytes));

        if (derivative == 2) {
            _updateVirtualPriceBound(derivativePerformData);
        } else if (derivative == 3) {
            _updateVirtualPriceBound(derivativePerformData);
        } else revert PriceRouter__UnkownDerivative(derivative);
    }

    // ======================================= PRICING OPERATIONS =======================================

    /**
     * @notice Get `asset` price in USD.
     * @dev Returns price in USD with 8 decimals.
     */
    function getPriceInUSD(ERC20 asset) external view returns (uint256) {
        AssetSettings memory assetSettings = getAssetSettings[asset];
        // Create an empty Price Cache.
        PriceCache[PRICE_CACHE_SIZE] memory cache;
        return _getPriceInUSD(asset, assetSettings, cache);
    }

    /**
     * @notice Get the value of an asset in terms of another asset.
     * @param baseAsset address of the asset to get the price of in terms of the quote asset
     * @param amount amount of the base asset to price
     * @param quoteAsset address of the asset that the base asset is priced in terms of
     * @return value value of the amount of base assets specified in terms of the quote asset
     */
    function getValue(ERC20 baseAsset, uint256 amount, ERC20 quoteAsset) external view returns (uint256 value) {
        AssetSettings memory baseSettings = getAssetSettings[baseAsset];
        AssetSettings memory quoteSettings = getAssetSettings[quoteAsset];
        if (baseSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(baseAsset));
        if (quoteSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(quoteAsset));
        PriceCache[PRICE_CACHE_SIZE] memory cache;
        uint256 priceBaseUSD = _getPriceInUSD(baseAsset, baseSettings, cache);
        uint256 priceQuoteUSD = _getPriceInUSD(quoteAsset, quoteSettings, cache);
        value = _getValueInQuote(priceBaseUSD, priceQuoteUSD, baseAsset.decimals(), quoteAsset.decimals(), amount);
    }

    /**
     * @notice Helper function that compares `_getValues` between input 0 and input 1.
     */
    function getValuesDelta(
        ERC20[] calldata baseAssets0,
        uint256[] calldata amounts0,
        ERC20[] calldata baseAssets1,
        uint256[] calldata amounts1,
        ERC20 quoteAsset
    ) external view returns (uint256) {
        // Create an empty Price Cache.
        PriceCache[PRICE_CACHE_SIZE] memory cache;

        uint256 value0 = _getValues(baseAssets0, amounts0, quoteAsset, cache);
        uint256 value1 = _getValues(baseAssets1, amounts1, quoteAsset, cache);
        return value0 - value1;
    }

    /**
     * @notice Helper function that determines the value of assets using `_getValues`.
     */
    function getValues(
        ERC20[] calldata baseAssets,
        uint256[] calldata amounts,
        ERC20 quoteAsset
    ) external view returns (uint256) {
        // Create an empty Price Cache.
        PriceCache[PRICE_CACHE_SIZE] memory cache;

        return _getValues(baseAssets, amounts, quoteAsset, cache);
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
    function getExchangeRates(
        ERC20[] memory baseAssets,
        ERC20 quoteAsset
    ) external view returns (uint256[] memory exchangeRates) {
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
        uint256 basePrice = _getPriceInUSD(baseAsset, baseSettings, cache);
        uint256 quotePrice = _getPriceInUSD(quoteAsset, quoteSettings, cache);
        uint256 exchangeRate = basePrice.mulDivDown(10 ** quoteAssetDecimals, quotePrice);
        return exchangeRate;
    }

    /**
     * @notice Helper function to get an assets price in USD.
     * @dev Returns price in USD with 8 decimals.
     * @dev Favors using cached prices if available.
     */
    function _getPriceInUSD(
        ERC20 asset,
        AssetSettings memory settings,
        PriceCache[PRICE_CACHE_SIZE] memory cache
    ) internal view returns (uint256) {
        // First check if the price is in the price cache.
        uint8 lastIndex = PRICE_CACHE_SIZE;
        for (uint8 i; i < PRICE_CACHE_SIZE; ++i) {
            // Did not find our price in the cache.
            if (cache[i].asset == address(0)) {
                // Save the last index.
                lastIndex = i;
                break;
            }
            // Did find our price in the cache.
            if (cache[i].asset == address(asset)) return cache[i].price;
        }

        // Call get price function using appropriate derivative.
        uint256 price;
        if (settings.derivative == 1) {
            price = _getPriceForChainlinkDerivative(asset, settings.source, cache);
        } else if (settings.derivative == 2) {
            price = _getPriceForCurveDerivative(asset, settings.source, cache);
        } else if (settings.derivative == 3) {
            price = _getPriceForCurveV2Derivative(asset, settings.source, cache);
        } else if (settings.derivative == 4) {
            price = _getPriceForAaveDerivative(asset, settings.source, cache);
        } else revert PriceRouter__UnkownDerivative(settings.derivative);

        // If there is room in the cache, the price fits in a uint96, then find the next spot available.
        if (lastIndex < PRICE_CACHE_SIZE && price <= type(uint96).max) {
            for (uint8 i = lastIndex; i < PRICE_CACHE_SIZE; ++i) {
                // Found an empty cache slot, so fill it.
                if (cache[i].asset == address(0)) {
                    cache[i] = PriceCache(address(asset), uint96(price));
                    break;
                }
            }
        }

        return price;
    }

    /**
     * @notice math function that preserves precision by multiplying the amountBase before dividing.
     * @param priceBaseUSD the base asset price in USD
     * @param priceQuoteUSD the quote asset price in USD
     * @param baseDecimals the base asset decimals
     * @param quoteDecimals the quote asset decimals
     * @param amountBase the amount of base asset
     */
    function _getValueInQuote(
        uint256 priceBaseUSD,
        uint256 priceQuoteUSD,
        uint8 baseDecimals,
        uint8 quoteDecimals,
        uint256 amountBase
    ) internal pure returns (uint256 valueInQuote) {
        // Get value in quote asset, but maintain as much precision as possible.
        // Cleaner equations below.
        // baseToUSD = amountBase * priceBaseUSD / 10**baseDecimals.
        // valueInQuote = baseToUSD * 10**quoteDecimals / priceQuoteUSD
        valueInQuote = amountBase.mulDivDown(
            (priceBaseUSD * 10 ** quoteDecimals),
            (10 ** baseDecimals * priceQuoteUSD)
        );
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
    function _getValues(
        ERC20[] calldata baseAssets,
        uint256[] calldata amounts,
        ERC20 quoteAsset,
        PriceCache[PRICE_CACHE_SIZE] memory cache
    ) internal view returns (uint256) {
        if (baseAssets.length != amounts.length) revert PriceRouter__LengthMismatch();
        uint256 quotePrice;
        {
            AssetSettings memory quoteSettings = getAssetSettings[quoteAsset];
            if (quoteSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(quoteAsset));
            quotePrice = _getPriceInUSD(quoteAsset, quoteSettings, cache);
        }
        uint256 valueInQuote;
        // uint256 price;
        uint8 quoteDecimals = quoteAsset.decimals();

        for (uint8 i = 0; i < baseAssets.length; i++) {
            // Skip zero amount values.
            if (amounts[i] == 0) continue;
            ERC20 baseAsset = baseAssets[i];
            if (baseAsset == quoteAsset) valueInQuote += amounts[i];
            else {
                uint256 basePrice;
                {
                    AssetSettings memory baseSettings = getAssetSettings[baseAsset];
                    if (baseSettings.derivative == 0) revert PriceRouter__UnsupportedAsset(address(baseAsset));
                    basePrice = _getPriceInUSD(baseAsset, baseSettings, cache);
                }
                valueInQuote += _getValueInQuote(
                    basePrice,
                    quotePrice,
                    baseAsset.decimals(),
                    quoteDecimals,
                    amounts[i]
                );
                // uint256 valueInUSD = (amounts[i].mulDivDown(price, 10**baseAsset.decimals()));
                // valueInQuote += valueInUSD.mulDivDown(10**quoteDecimals, quotePrice);
            }
        }
        return valueInQuote;
    }

    // =========================================== CHAINLINK PRICE DERIVATIVE ===========================================\
    /**
     * @notice Stores data for Chainlink derivative assets.
     * @param max the max valid price of the asset
     * @param min the min valid price of the asset
     * @param heartbeat the max amount of time between price updates
     * @param inETH bool indicating whether the price feed is
     *        denominated in ETH(true) or USD(false)
     */
    struct ChainlinkDerivativeStorage {
        uint144 max;
        uint80 min;
        uint24 heartbeat;
        bool inETH;
    }
    /**
     * @notice Returns Chainlink Derivative Storage
     */
    mapping(ERC20 => ChainlinkDerivativeStorage) public getChainlinkDerivativeStorage;

    /**
     * @notice If zero is specified for a Chainlink asset heartbeat, this value is used instead.
     */
    uint24 public constant DEFAULT_HEART_BEAT = 1 days;

    /**
     * @notice Setup function for pricing Chainlink derivative assets.
     * @dev _source The address of the Chainlink Data feed.
     * @dev _storage A ChainlinkDerivativeStorage value defining valid prices.
     */
    function _setupPriceForChainlinkDerivative(ERC20 _asset, address _source, bytes memory _storage) internal {
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

    /**
     * @notice Get the price of a Chainlink derivative in terms of USD.
     */
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
     * @param max the upper price bound
     * @param min the lower price bound
     * @param heartbeat the max amount of time between price updates
     */
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

    // ======================================== CURVE VIRTUAL PRICE BOUND ========================================
    /**
     * @notice Curve virtual price is susceptible to re-entrancy attacks, if the attacker adds/removes pool liquidity,
     *         and re-enters into one of our contracts. To mitigate this, all curve pricing operations check
     *         the current `pool.get_virtual_price()` against logical bounds.
     * @notice These logical bounds are updated when `addAsset` is called, or Chainlink Automation detects that
     *         the bounds need to be updated, and that the gas price is reasonable.
     * @notice Once the on chain virtual price goes out of bounds, all pricing operations will revert for that Curve LP,
     *         which means any Cellars using that Curve LP are effectively frozen until the virtual price bounds are updated
     *         by Chainlink. If this is not happening in a timely manner( IE network is abnormally busy), the owner of this
     *         contract can raise the `gasConstant` to a value that better reflects the floor gas price of the network.
     *         Which will cause Chainlink nodes to update virtual price bounds faster.
     */

    /**
     * @param datum the virtual price to base posDelta and negDelta off of, 8 decimals
     * @param timeLastUpdated the timestamp this datum was updated
     * @param posDelta multipler >= 1e8 defining the logical upper bound for this virtual price, 8 decimals
     * @param negDelta multipler <= 1e8 defining the logical lower bound for this virtual price, 8 decimals
     * @param rateLimit the minimum amount of time that must pass between updates
     * @dev Curve virtual price values should update slowly, hence why this contract enforces a rate limit.
     * @dev During datum updates, the max/min new datum corresponds to the current upper/lower bound.
     */
    struct VirtualPriceBound {
        uint96 datum;
        uint64 timeLastUpdated;
        uint32 posDelta;
        uint32 negDelta;
        uint32 rateLimit;
    }

    /**
     * @notice Returns a Curve asset virtual price bound
     */
    mapping(address => VirtualPriceBound) public getVirtualPriceBound;

    /**
     * @dev If ZERO is specified for an assets `rateLimit` this value is used instead.
     */
    uint32 public constant DEFAULT_RATE_LIMIT = 1 days;

    /**
     * @notice Chainlink Fast Gas Feed for ETH Mainnet.
     */
    address public ETH_FAST_GAS_FEED = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    /**
     * @notice Allows owner to set a new gas feed.
     * @notice Can be set to zero address to skip gas check.
     */
    function setGasFeed(address gasFeed) external onlyOwner {
        ETH_FAST_GAS_FEED = gasFeed;
    }

    /**
     * @notice Dictates how aggressive keepers are with updating Curve pool virtual price values.
     * @dev A larger `gasConstant` will raise the `gasPriceLimit`, while a smaller `gasConstant`
     *      will lower the `gasPriceLimit`.
     */
    uint256 public gasConstant = 200e9;

    /**
     * @notice Allows owner to set a new gas constant.
     */
    function setGasConstant(uint256 newConstant) external onlyOwner {
        gasConstant = newConstant;
    }

    /**
     * @notice Dictates the minimum delta required for an upkeep.
     * @dev If the max delta found is less than this, then checkUpkeep returns false.
     */
    uint256 public minDelta = 0.05e18;

    /**
     * @notice Allows owner to set a new minimum delta.
     */
    function setMinDelta(uint256 newMinDelta) external onlyOwner {
        minDelta = newMinDelta;
    }

    /**
     * @notice Stores all Curve Assets this contract prices, so Automation can loop through it.
     */
    address[] public curveAssets;

    /**
     * @notice Allows owner to update a Curve asset's virtual price parameters..
     */
    function updateVirtualPriceBound(
        address _asset,
        uint32 _posDelta,
        uint32 _negDelta,
        uint32 _rateLimit
    ) external onlyOwner {
        VirtualPriceBound storage vpBound = getVirtualPriceBound[_asset];
        vpBound.posDelta = _posDelta;
        vpBound.negDelta = _negDelta;
        vpBound.rateLimit = _rateLimit == 0 ? DEFAULT_RATE_LIMIT : _rateLimit;
    }

    /**
     * @notice Logic ran by Chainlink Automation to determine if virtual price bounds need to be updated.
     * @dev `checkData` should be a start and end value indicating where to start and end in the `curveAssets` array.
     * @dev The end index can be zero, or greater than the current length of `curveAssets`.
     *      Doing this makes end = curveAssets.length.
     * @dev `performData` is the target index in `curveAssets` that needs its bounds updated.
     */
    function _checkVirtualPriceBound(
        bytes memory checkData
    ) internal view returns (bool upkeepNeeded, bytes memory performData) {
        // Decode checkData to get start and end index.
        (uint256 start, uint256 end) = abi.decode(checkData, (uint256, uint256));
        if (end == 0 || end > curveAssets.length) end = curveAssets.length;

        // Loop through all curve assets, and find the asset with the largest delta(the one that needs to be updated the most).
        uint256 maxDelta;
        uint256 targetIndex;
        for (uint256 i = start; i < end; i++) {
            address asset = curveAssets[i];
            VirtualPriceBound memory vpBound = getVirtualPriceBound[asset];

            // Check to see if this virtual price was updated recently.
            if ((block.timestamp - vpBound.timeLastUpdated) < vpBound.rateLimit) continue;

            // Check current virtual price against upper and lower bounds to find the delta.
            uint256 currentVirtualPrice = ICurvePool(getAssetSettings[ERC20(asset)].source).get_virtual_price();
            currentVirtualPrice = currentVirtualPrice.changeDecimals(18, 8);
            uint256 delta;
            if (currentVirtualPrice > vpBound.datum) {
                uint256 upper = uint256(vpBound.datum).mulDivDown(vpBound.posDelta, 1e8);
                uint256 ceiling = upper - vpBound.datum;
                uint256 current = currentVirtualPrice - vpBound.datum;
                delta = _getDelta(ceiling, current);
            } else {
                uint256 lower = uint256(vpBound.datum).mulDivDown(vpBound.negDelta, 1e8);
                uint256 ceiling = vpBound.datum - lower;
                uint256 current = vpBound.datum - currentVirtualPrice;
                delta = _getDelta(ceiling, current);
            }
            // Save the largest delta for the upkeep.
            if (delta > maxDelta) {
                maxDelta = delta;
                targetIndex = i;
            }
        }

        // If the largest delta must be greater/equal to `minDelta` to continue.
        if (maxDelta >= minDelta) {
            // If gas feed is not set, skip the gas check.
            if (ETH_FAST_GAS_FEED == address(0)) {
                // No Gas Check needed.
                upkeepNeeded = true;
                performData = abi.encode(targetIndex);
            } else {
                // Run a gas check to determine if it makes sense to update the target curve asset.
                uint256 gasPriceLimit = gasConstant.mulDivDown(maxDelta ** 3, 1e54); // 54 comes from 18 * 3.
                uint256 currentGasPrice = uint256(IChainlinkAggregator(ETH_FAST_GAS_FEED).latestAnswer());
                if (currentGasPrice <= gasPriceLimit) {
                    upkeepNeeded = true;
                    performData = abi.encode(targetIndex);
                }
            }
        }
    }

    /**
     * @notice Attempted to call a function only the Chainlink Registry can call.
     */
    error PriceRouter__OnlyAutomationRegistry();

    /**
     * @notice Attempted to update a virtual price too soon.
     */
    error PriceRouter__VirtualPriceRateLimiter();

    /**
     * @notice Attempted to update a virtual price bound that did not need to be updated.
     */
    error PriceRouter__NothingToUpdate();

    /**
     * @notice Chainlink's Automation Registry contract address.
     */
    address public automationRegistry = 0x02777053d6764996e594c3E88AF1D58D5363a2e6;

    /**
     * @notice Allows owner to update the Automation Registry.
     * @dev In rare cases, Chainlink's registry CAN change.
     */
    function setAutomationRegistry(address newRegistry) external onlyOwner {
        automationRegistry = newRegistry;
    }

    /**
     * @notice Curve virtual price is susceptible to re-entrancy attacks, if the attacker adds/removes pool liquidity.
     *         To stop this we check the virtual price against logical bounds.
     * @dev Only the chainlink registry can call this function, so we know that Chainlink nodes will not be
     *      re-entering into the Curve pool, so it is safe to use the current on chain virtual price.
     * @notice Updating the virtual price is rate limited by `VirtualPriceBound.raetLimit` and can only be
     *         updated at most to the lower or upper bound of the current datum.
     *         This is intentional since curve pool price should not be volatile, and if they are, then
     *         we WANT that Curve LP pools TX pricing to revert.
     */
    function _updateVirtualPriceBound(bytes memory performData) internal {
        // Make sure only the Automation Registry can call this function.
        if (msg.sender != automationRegistry) revert PriceRouter__OnlyAutomationRegistry();

        // Grab the target index from performData.
        uint256 index = abi.decode(performData, (uint256));
        address asset = curveAssets[index];
        VirtualPriceBound storage vpBound = getVirtualPriceBound[asset];

        // Enfore rate limit check.
        if ((block.timestamp - vpBound.timeLastUpdated) < vpBound.rateLimit)
            revert PriceRouter__VirtualPriceRateLimiter();

        // Determine what the new Datum should be.
        uint256 currentVirtualPrice = ICurvePool(getAssetSettings[ERC20(asset)].source).get_virtual_price();
        currentVirtualPrice = currentVirtualPrice.changeDecimals(18, 8);
        if (currentVirtualPrice > vpBound.datum) {
            uint256 upper = uint256(vpBound.datum).mulDivDown(vpBound.posDelta, 1e8);
            vpBound.datum = uint96(currentVirtualPrice > upper ? upper : currentVirtualPrice);
        } else if (currentVirtualPrice < vpBound.datum) {
            uint256 lower = uint256(vpBound.datum).mulDivDown(vpBound.negDelta, 1e8);
            vpBound.datum = uint96(currentVirtualPrice < lower ? lower : currentVirtualPrice);
        } else {
            revert PriceRouter__NothingToUpdate();
        }

        // Update the stored timestamp.
        vpBound.timeLastUpdated = uint64(block.timestamp);
    }

    /**
     * @notice Returns a percent delta representing where `current` is in reference to `ceiling`.
     * Example, if current == 0, this would return a 0.
     *          if current == ceiling, this would return a 1e18.
     *          if current == (ceiling) / 2, this would return 0.5e18.
     */
    function _getDelta(uint256 ceiling, uint256 current) internal pure returns (uint256) {
        return current.mulDivDown(1e18, ceiling);
    }

    /**
     * @notice Attempted to price a curve asset that was below its logical minimum price.
     */
    error PriceRouter__CurrentBelowLowerBound(uint256 current, uint256 lower);

    /**
     * @notice Attempted to price a curve asset that was above its logical maximum price.
     */
    error PriceRouter__CurrentAboveUpperBound(uint256 current, uint256 upper);

    /**
     * @notice Enforces a logical price bound on Curve pool tokens.
     */
    function _checkBounds(uint256 lower, uint256 upper, uint256 current) internal pure {
        if (current < lower) revert PriceRouter__CurrentBelowLowerBound(current, lower);
        if (current > upper) revert PriceRouter__CurrentAboveUpperBound(current, upper);
    }

    // =========================================== CURVE PRICE DERIVATIVE ===========================================
    /**
     * @notice Curve Derivative Storage
     * @dev Stores an array of the underlying token addresses in the curve pool.
     */
    mapping(ERC20 => address[]) public getCurveDerivativeStorage;

    /**
     * @notice Setup function for pricing Curve derivative assets.
     * @dev _source The address of the Curve Pool.
     * @dev _storage A VirtualPriceBound value for this asset.
     * @dev Assumes that curve pools never add or remove tokens.
     */
    function _setupPriceForCurveDerivative(ERC20 _asset, address _source, bytes memory _storage) internal {
        ICurvePool pool = ICurvePool(_source);
        uint8 coinsLength = 0;
        // Figure out how many tokens are in the curve pool.
        while (true) {
            try pool.coins(coinsLength) {
                coinsLength++;
            } catch {
                break;
            }
        }

        // Save the pools tokens to reduce gas for pricing calls.
        address[] memory coins = new address[](coinsLength);
        for (uint256 i = 0; i < coinsLength; i++) {
            coins[i] = pool.coins(i);
        }

        getCurveDerivativeStorage[_asset] = coins;

        curveAssets.push(address(_asset));

        // Setup virtual price bound.
        VirtualPriceBound memory vpBound = abi.decode(_storage, (VirtualPriceBound));
        uint256 upper = uint256(vpBound.datum).mulDivDown(vpBound.posDelta, 1e8);
        upper = upper.changeDecimals(8, 18);
        uint256 lower = uint256(vpBound.datum).mulDivDown(vpBound.negDelta, 1e8);
        lower = lower.changeDecimals(8, 18);
        _checkBounds(lower, upper, pool.get_virtual_price());
        if (vpBound.rateLimit == 0) vpBound.rateLimit = DEFAULT_RATE_LIMIT;
        vpBound.timeLastUpdated = uint64(block.timestamp);
        getVirtualPriceBound[address(_asset)] = vpBound;
    }

    /**
     * @notice Get the price of a CurveV1 derivative in terms of USD.
     */
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

        // Check that virtual price is within bounds.
        uint256 virtualPrice = pool.get_virtual_price();
        VirtualPriceBound memory vpBound = getVirtualPriceBound[address(asset)];
        uint256 upper = uint256(vpBound.datum).mulDivDown(vpBound.posDelta, 1e8);
        upper = upper.changeDecimals(8, 18);
        uint256 lower = uint256(vpBound.datum).mulDivDown(vpBound.negDelta, 1e8);
        lower = lower.changeDecimals(8, 18);
        _checkBounds(lower, upper, virtualPrice);

        // Virtual price is based off the Curve Token decimals.
        uint256 curveTokenDecimals = ERC20(asset).decimals();
        price = minPrice.mulDivDown(virtualPrice, 10 ** curveTokenDecimals);
    }

    // =========================================== CURVEV2 PRICE DERIVATIVE ===========================================

    /**
     * @notice Setup function for pricing CurveV2 derivative assets.
     * @dev _source The address of the CurveV2 Pool.
     * @dev _storage A VirtualPriceBound value for this asset.
     * @dev Assumes that curve pools never add or remove tokens.
     */
    function _setupPriceForCurveV2Derivative(ERC20 _asset, address _source, bytes memory _storage) internal {
        ICurvePool pool = ICurvePool(_source);
        uint8 coinsLength = 0;
        // Figure out how many tokens are in the curve pool.
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

        curveAssets.push(address(_asset));

        // Setup virtual price bound.
        VirtualPriceBound memory vpBound = abi.decode(_storage, (VirtualPriceBound));
        uint256 upper = uint256(vpBound.datum).mulDivDown(vpBound.posDelta, 1e8);
        upper = upper.changeDecimals(8, 18);
        uint256 lower = uint256(vpBound.datum).mulDivDown(vpBound.negDelta, 1e8);
        lower = lower.changeDecimals(8, 18);
        _checkBounds(lower, upper, pool.get_virtual_price());
        if (vpBound.rateLimit == 0) vpBound.rateLimit = DEFAULT_RATE_LIMIT;
        vpBound.timeLastUpdated = uint64(block.timestamp);
        getVirtualPriceBound[address(_asset)] = vpBound;
    }

    uint256 private constant GAMMA0 = 28000000000000;
    uint256 private constant A0 = 2 * 3 ** 3 * 10000;
    uint256 private constant DISCOUNT0 = 1087460000000000;

    // x has 36 decimals
    // result has 18 decimals.
    function _cubicRoot(uint256 x) internal pure returns (uint256) {
        uint256 D = x / 1e18;
        for (uint8 i; i < 256; i++) {
            uint256 diff;
            uint256 D_prev = D;
            D = (D * (2 * 1e18 + ((((x / D) * 1e18) / D) * 1e18) / D)) / (3 * 1e18);
            if (D > D_prev) diff = D - D_prev;
            else diff = D_prev - D;
            if (diff <= 1 || diff * 10 ** 18 < D) return D;
        }
        revert("Did not converge");
    }

    /**
     * Inspired by https://etherscan.io/address/0xE8b2989276E2Ca8FDEA2268E3551b2b4B2418950#code
     * @notice Get the price of a CurveV1 derivative in terms of USD.
     */
    function _getPriceForCurveV2Derivative(
        ERC20 asset,
        address _source,
        PriceCache[PRICE_CACHE_SIZE] memory cache
    ) internal view returns (uint256) {
        ICurvePool pool = ICurvePool(_source);

        // Check that virtual price is within bounds.
        uint256 virtualPrice = pool.get_virtual_price();
        VirtualPriceBound memory vpBound = getVirtualPriceBound[address(asset)];
        uint256 upper = uint256(vpBound.datum).mulDivDown(vpBound.posDelta, 1e8);
        upper = upper.changeDecimals(8, 18);
        uint256 lower = uint256(vpBound.datum).mulDivDown(vpBound.negDelta, 1e8);
        lower = lower.changeDecimals(8, 18);
        _checkBounds(lower, upper, virtualPrice);

        address[] memory coins = getCurveDerivativeStorage[asset];
        ERC20 token0 = ERC20(coins[0]);
        if (coins.length == 2) {
            return pool.lp_price().mulDivDown(_getPriceInUSD(token0, getAssetSettings[token0], cache), 1e18);
        } else if (coins.length == 3) {
            uint256 t1Price = pool.price_oracle(0);
            uint256 t2Price = pool.price_oracle(1);

            uint256 maxPrice = (3 * virtualPrice * _cubicRoot(t1Price * t2Price)) / 1e18;
            {
                uint256 g = pool.gamma().mulDivDown(1e18, GAMMA0);
                uint256 a = pool.A().mulDivDown(1e18, A0);
                uint256 coefficient = (g ** 2 / 1e18) * a;
                uint256 discount = coefficient > 1e34 ? coefficient : 1e34;
                discount = _cubicRoot(discount).mulDivDown(DISCOUNT0, 1e18);

                maxPrice -= maxPrice.mulDivDown(discount, 1e18);
            }
            return maxPrice.mulDivDown(_getPriceInUSD(token0, getAssetSettings[token0], cache), 1e18);
        } else revert("Unsupported Pool");
    }

    // =========================================== AAVE PRICE DERIVATIVE ===========================================
    /**
     * @notice Aave Derivative Storage
     */
    mapping(ERC20 => ERC20) public getAaveDerivativeStorage;

    /**
     * @notice Setup function for pricing Aave derivative assets.
     * @dev _source The address of the aToken.
     * @dev _storage is not used.
     */
    function _setupPriceForAaveDerivative(ERC20 _asset, address _source, bytes memory) internal {
        IAaveToken aToken = IAaveToken(_source);
        getAaveDerivativeStorage[_asset] = ERC20(aToken.UNDERLYING_ASSET_ADDRESS());
    }

    /**
     * @notice Get the price of an Aave derivative in terms of USD.
     */
    function _getPriceForAaveDerivative(
        ERC20 asset,
        address,
        PriceCache[PRICE_CACHE_SIZE] memory cache
    ) internal view returns (uint256) {
        asset = getAaveDerivativeStorage[asset];
        return _getPriceInUSD(asset, getAssetSettings[asset], cache);
    }
}
