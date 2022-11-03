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
    // struct AssetConfig {
    //     uint256 minPrice;
    //     uint256 maxPrice;
    //     bool isPriceRangeInETH;
    //     uint96 heartbeat;
    //     bool isSupported;
    // }

    /**
     * @notice Stores bare minimum settings all derivatives support like so.
     * 256 Bit
     * uint80 Reserved for future use.
     * uint8 Storage used.
     * uint160 Source address: Where does this contract look to handle pricing.
     * uint8 Derivative: Note 0 is an invalid Derivative.
     * 0 Bit
     */
    mapping(ERC20 => uint256) public getAssetSettings; // maps an asset -> settings

    /**
     * @notice Arbitrary storage that derivatives can use.
     */
    mapping(ERC20 => uint256) public getAssetStorage;

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

    /**
     * @notice Attempted to add an asset with a certain price range denomination, but actual denomination was different.
     * @param expected price range denomination
     * @param actual price range denomination
     * @dev If an asset has price feeds in USD and ETH, the feed in USD is favored
     */
    error PriceRouter__PriceRangeDenominationMisMatch(bool expected, bool actual);

    error PriceRouter__BadAnswer(uint256 answer, uint256 expectedAnswer);

    /**
     * @notice Attempted to add an asset with invalid min/max prices.
     * @param min price
     * @param max price
     */
    error PriceRouter__MinPriceGreaterThanMaxPrice(uint256 min, uint256 max);

    function readSettingsForDerivative(uint256 _settings)
        public
        pure
        returns (
            address source,
            uint8 derivative,
            bool usesStorage
        )
    {
        usesStorage = uint8(_settings >> 168) == 1;
        source = address(uint160(_settings >> 8));
        derivative = uint8(_settings);
    }

    function createSettingsForDerivative(
        address source,
        uint8 derivative,
        bool usesStorage
    ) public pure returns (uint256 settings) {
        settings |= uint256(derivative);
        settings |= uint256(uint256(uint160(source)) << 8);
        settings |= uint256(uint256(usesStorage ? 1 : 0) << 168);
    }

    uint256 public constant EXPECTED_ANSWER_DEVIATION = 0.02e18;

    function addAsset(
        ERC20 _asset,
        uint256 _settings,
        uint256 _storage,
        uint256 _expectedAnswer
    ) external onlyOwner {
        if (address(_asset) == address(0)) revert PriceRouter__InvalidAsset(address(_asset));
        (address source, uint8 derivative, bool usesStorage) = readSettingsForDerivative(_settings);
        if (derivative == 0) revert("Invalid Derivative");
        if (derivative == 1) {
            _storage = _setupPriceForChainlinkDerivative(source, _storage);
        } //else if (_priceDerivative == PriceDerivative.CURVE) {
        //     _settings = _setupPriceForCurveDerivative(_asset, _settings, _storage);
        // }

        getAssetSettings[_asset] = _settings;
        getAssetStorage[_asset] = usesStorage ? _storage : 0;

        uint256 minAnswer = _expectedAnswer.mulWadDown((1e18 - EXPECTED_ANSWER_DEVIATION));
        uint256 maxAnswer = _expectedAnswer.mulWadDown((1e18 + EXPECTED_ANSWER_DEVIATION));

        (uint256 answer, ) = _getPriceInUSD(_asset, _settings, 0);

        if (answer < minAnswer || answer > maxAnswer) revert PriceRouter__BadAnswer(answer, _expectedAnswer);

        emit AddAsset(address(_asset));
    }

    /**
     * @notice return bool indicating whether or not an asset has been set up.
     * @dev Since `addAsset` enforces the derivative is non zero, checking if the stored setting
     *      is nonzero is sufficient to see if the asset is set up.
     */
    function isSupported(ERC20 asset) external view returns (bool) {
        return getAssetSettings[asset] > 0;
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
    ) external view returns (uint256) {
        uint256 numOfAssets = baseAssets.length;
        if (numOfAssets != amounts.length) revert PriceRouter__LengthMismatch();

        uint256 ethToUsd;
        uint256 quoteSettings;
        if ((quoteSettings = getAssetSettings[quoteAsset]) == 0)
            revert PriceRouter__UnsupportedAsset(address(quoteAsset));

        uint256 valueInUSD;
        uint256 price;

        for (uint256 i = 0; i < numOfAssets; i++) {
            // Skip zero amount values.
            if (amounts[i] == 0) continue;
            ERC20 baseAsset = baseAssets[i];
            uint256 baseSettings;
            if ((baseSettings = getAssetSettings[baseAsset]) == 0)
                revert PriceRouter__UnsupportedAsset(address(baseAsset));
            (price, ethToUsd) = _getPriceInUSD(baseAsset, baseSettings, ethToUsd);
            valueInUSD += amounts[i].mulDivDown(price, 10**baseAsset.decimals());
        }

        // Finally get quoteAsset price in USD.
        (price, ethToUsd) = _getPriceInUSD(quoteAsset, quoteSettings, ethToUsd);

        return valueInUSD.mulDivDown(10**quoteAsset.decimals(), price);
    }

    /**
     * @notice Get the exchange rate between two assets.
     * @param baseAsset address of the asset to get the exchange rate of in terms of the quote asset
     * @param quoteAsset address of the asset that the base asset is exchanged for
     * @return exchangeRate rate of exchange between the base asset and the quote asset
     */
    function getExchangeRate(ERC20 baseAsset, ERC20 quoteAsset) public view returns (uint256 exchangeRate) {
        uint256 baseSettings;
        uint256 quoteSettings;
        if ((baseSettings = getAssetSettings[baseAsset]) == 0) revert PriceRouter__UnsupportedAsset(address(baseAsset));
        if ((quoteSettings = getAssetSettings[quoteAsset]) == 0)
            revert PriceRouter__UnsupportedAsset(address(quoteAsset));
        // Pass in zero for ethToUsd, since it has not been set yet.
        (exchangeRate, ) = _getExchangeRate(
            baseAsset,
            baseSettings,
            quoteAsset,
            quoteSettings,
            quoteAsset.decimals(),
            0
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
        uint256 ethToUsd;
        uint256 quoteSettings;
        if ((quoteSettings = getAssetSettings[quoteAsset]) == 0)
            revert PriceRouter__UnsupportedAsset(address(quoteAsset));

        uint256 numOfAssets = baseAssets.length;
        exchangeRates = new uint256[](numOfAssets);
        for (uint256 i; i < numOfAssets; i++) {
            uint256 baseSettings = getAssetSettings[baseAssets[i]];
            (exchangeRates[i], ethToUsd) = _getExchangeRate(
                baseAssets[i],
                baseSettings,
                quoteAsset,
                quoteSettings,
                quoteAssetDecimals,
                ethToUsd
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
        uint256 baseSettings,
        ERC20 quoteAsset,
        uint256 quoteSettings,
        uint8 quoteAssetDecimals,
        uint256 ethToUsd
    ) internal view returns (uint256, uint256) {
        uint256 basePrice;
        uint256 quotePrice;
        (basePrice, ethToUsd) = _getPriceInUSD(baseAsset, baseSettings, ethToUsd);
        (quotePrice, ethToUsd) = _getPriceInUSD(quoteAsset, quoteSettings, ethToUsd);
        uint256 exchangeRate = basePrice.mulDivDown(10**quoteAssetDecimals, quotePrice);
        return (exchangeRate, ethToUsd);
    }

    function _getPriceInUSD(
        ERC20 baseAsset,
        uint256 settings,
        uint256 ethToUsd
    ) internal view returns (uint256, uint256) {
        (address source, uint8 derivative, bool usesStorage) = readSettingsForDerivative(settings);
        uint256 exchangeRate;
        uint256 _storage;
        if (usesStorage) _storage = getAssetStorage[baseAsset];

        if (derivative == 1) {
            (exchangeRate, ethToUsd) = _getPriceForChainlinkDerivative(address(baseAsset), source, _storage, ethToUsd);
        }

        return (exchangeRate, ethToUsd);
    }

    // =========================================== CHAINLINK PRICING FUNCTIONS ===========================================\
    /**
     * @notice Chainlink Derivative Storage is as follows
     * 256 bit
     * uint144 max
     * uint88 min
     * uint24 heartbeat
     * 0 bit
     */
    function _readStorageForChainlinkDerivative(uint256 _storage)
        internal
        pure
        returns (
            uint144 max,
            uint80 min,
            uint24 heartbeat,
            bool inETH
        )
    {
        max = uint144(_storage >> 112);
        min = uint80(_storage >> 32);
        heartbeat = uint24(_storage >> 8);
        inETH = uint8(_storage) == 1;
    }

    function createStorageForChainlinkDerivative(
        uint144 _max,
        uint80 _min,
        uint24 _heartbeat,
        bool _inETH
    ) public pure returns (uint256 _storage) {
        _storage |= uint256(_max) << 112;
        _storage |= uint256(_min) << 24;
        _storage |= uint256(_heartbeat) << 8;
        _storage |= uint256(_inETH ? 1 : 0);
    }

    function _setupPriceForChainlinkDerivative(address _source, uint256 _storage) internal view returns (uint256) {
        (uint144 max, uint80 min, uint24 heartbeat, bool inETH) = _readStorageForChainlinkDerivative(_storage);

        // Use Chainlink to get the min and max of the asset.
        IChainlinkAggregator aggregator = IChainlinkAggregator(IChainlinkAggregator(_source).aggregator());
        uint256 minFromChainklink = uint256(uint192(aggregator.minAnswer())); //TODO should use safe cast
        uint256 maxFromChainlink = uint256(uint192(aggregator.maxAnswer())); //But this one is probs fine without safecast

        // Add a ~10% buffer to minimum and maximum price from Chainlink because Chainlink can stop updating
        // its price before/above the min/max price.
        uint256 bufferedMinPrice = (minFromChainklink * 1.1e18) / 1e18;
        uint256 bufferedMaxPrice = (maxFromChainlink * 0.9e18) / 1e18;

        if (min == 0) {
            // Revert if bufferedMinPrice overflows because uint80 is too small to hold the minimum price,
            // and lowering it to uint80 is not safe because the price feed can stop being updated before
            // it actually gets to that lower price.
            if (bufferedMinPrice > type(uint80).max) revert("Buffered Min Overflow");
            min = uint80(bufferedMinPrice);
        } else {
            if (min < bufferedMinPrice) revert PriceRouter__InvalidMinPrice(min, bufferedMinPrice);
        }

        if (max == 0) {
            //Do not revert even if bufferedMaxPrice is greater than uint144, because lowering it to uint144 max is more conservative.
            max = bufferedMaxPrice > type(uint144).max ? type(uint144).max : uint144(bufferedMaxPrice);
        } else {
            if (max > bufferedMaxPrice) revert PriceRouter__InvalidMaxPrice(max, bufferedMaxPrice);
        }

        if (min >= max) revert PriceRouter__MinPriceGreaterThanMaxPrice(min, max);

        heartbeat = heartbeat != 0 ? heartbeat : DEFAULT_HEART_BEAT;

        return createStorageForChainlinkDerivative(max, min, heartbeat, inETH);
    }

    function _getPriceForChainlinkDerivative(
        address _asset,
        address _source,
        uint256 _storage,
        uint256 _ethToUsd
    ) internal view returns (uint256, uint256) {
        IChainlinkAggregator aggregator = IChainlinkAggregator(_source);
        (, int256 _price, , uint256 _timestamp, ) = aggregator.latestRoundData();
        uint256 price = _price.toUint256();
        (uint144 max, uint88 min, uint24 heartbeat, bool inETH) = _readStorageForChainlinkDerivative(_storage);
        _checkPriceFeed(_asset, price, _timestamp, max, min, heartbeat);
        if (inETH) {
            if (_ethToUsd == 0) {
                (_ethToUsd, ) = _getPriceInUSD(WETH, getAssetSettings[WETH], 0);
            }
            price = price.mulWadDown(_ethToUsd);
        }
        return (price, _ethToUsd);
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
}
