// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ChainlinkPriceFeedAdaptor } from "src/modules/price-router/adaptors/ChainlinkPriceFeedAdaptor.sol";
import { Math } from "src/utils/Math.sol";

import "src/Errors.sol";

/**
 * @title  Price Router
 * @notice Provides a universal interface allowing Sommelier contracts to retrieve secure pricing
 *         data from Chainlink and arbitrary adaptors.
 * @author crispymangoes, Brian Le
 */
contract PriceRouter is Ownable, ChainlinkPriceFeedAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    // =========================================== ASSETS CONFIG ===========================================

    /**
     * @param minPrice is the minimum price in USD for the asset before reverting
     * @param maxPrice is the maximum price in USD for the asset before reverting
     * @param heartbeat maximum allowed time that can pass with no update before price data is considered stale
     * @param isSupported whether this asset is supported by the platform or not
     */
    struct AssetData {
        ERC20 remap;
        uint256 minPrice;
        uint256 maxPrice;
        uint96 heartBeat; //maximum allowed time to pass with no update
        bool isSupported;
    }

    mapping(ERC20 => AssetData) public getAssetData;

    uint96 public constant DEFAULT_HEART_BEAT = 1 days;

    // ======================================= Adaptor OPERATIONS =======================================

    /**
     * @notice Add an asset for the price router to support.
     * @param asset address of asset to support on the platform
     * @param remap address of asset to use pricing data for instead if a price feed is not
     *              available (eg. ETH for WETH), set to `address(0)` for no remapping
     * @param minPrice minimum price in USD with 8 decimals for the asset before reverting,
     *                 set to `0` to use Chainlink's default
     * @param maxPrice maximum price in USD with 8 decimals for the asset before reverting,
     *                 set to `0` to use Chainlink's default
     * @param heartbeat maximum amount of time that can pass without the price data being updated
     *                  before reverting, set to `0` to use the default of 1 day
     */
    function addAsset(
        ERC20 asset,
        ERC20 remap,
        uint256 minPrice,
        uint256 maxPrice,
        uint96 heartbeat
    ) external onlyOwner {
        require(address(asset) != address(0), "Invalid asset");

        if (minPrice == 0 || maxPrice == 0) {
            // If no adaptor is specified, use the Chainlink to get the min and max of the asset.
            ERC20 assetToQuery = address(remap) == address(0) ? asset : remap;
            (uint256 minFromChainklink, uint256 maxFromChainlink) = _getPriceRangeInUSD(assetToQuery);

            if (minPrice == 0) minPrice = minFromChainklink;
            if (maxPrice == 0) maxPrice = maxFromChainlink;
        }

        getAssetData[asset] = AssetData({
            remap: remap,
            minPrice: minPrice,
            maxPrice: maxPrice,
            heartBeat: heartbeat != 0 ? heartbeat : DEFAULT_HEART_BEAT,
            isSupported: true
        });
    }

    /**
     * @notice Remove support for an asset, causing all operations that use the asset to revert.
     * @param asset address of asset to remove support for
     */
    function removeAsset(ERC20 asset) external onlyOwner {
        getAssetData[asset].isSupported = false;
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
        if (numOfAssets != amounts.length) revert USR_LengthMismatch();

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
    function getPriceRange(ERC20 asset) public view returns (uint256 min, uint256 max) {
        AssetData storage assetData = getAssetData[asset];

        (min, max) = (assetData.minPrice, assetData.maxPrice);
    }

    /**
     * @notice Get the minimum and maximum valid prices for an asset.
     * @param assets addresses of the assets to get the price ranges for
     * @return min minimum valid price for each asset
     * @return max maximum valid price for each asset
     */
    function getPriceRanges(ERC20[] memory assets) external view returns (uint256[] memory min, uint256[] memory max) {
        uint256 numOfAssets = assets.length;
        (min, max) = (new uint256[](numOfAssets), new uint256[](numOfAssets));
        for (uint256 i; i < numOfAssets; i++) (min[i], max[i]) = getPriceRange(assets[i]);
    }

    // =========================================== HELPER FUNCTIONS ===========================================

    /**
     * @notice Gets the exchange rate between a base and a quote asset
     * @param baseAsset the asset to convert into quoteAsset
     * @param quoteAsset the asset base asset is converted into
     * @return exchangeRate baseAsset/quoteAsset
     * if base is ETH and quote is USD
     * would return ETH/USD
     */
    function _getExchangeRate(
        ERC20 baseAsset,
        ERC20 quoteAsset,
        uint8 quoteAssetDecimals
    ) internal view returns (uint256 exchangeRate) {
        exchangeRate = _getValueInUSD(baseAsset).mulDivDown(10**quoteAssetDecimals, _getValueInUSD(quoteAsset));
    }

    /**
     * @notice Gets the valuation of some asset in USD
     * @dev USD valuation has 8 decimals
     * @param asset the asset to get the value of in USD
     * @return value the value of asset in USD
     */
    function _getValueInUSD(ERC20 asset) internal view returns (uint256 value) {
        AssetData storage assetData = getAssetData[asset];

        if (!assetData.isSupported) revert USR_UnsupportedAsset(address(asset));

        if (address(assetData.remap) != address(0)) asset = assetData.remap;

        uint256 timestamp;
        (value, timestamp) = _getValueInUSDAndTimestamp(asset);

        uint256 minPrice = assetData.minPrice;
        if (value < minPrice) revert STATE_AssetBelowMinPrice(address(asset), value, minPrice);

        uint256 maxPrice = assetData.maxPrice;
        if (value > maxPrice) revert STATE_AssetAboveMaxPrice(address(asset), value, maxPrice);

        uint256 heartbeat = assetData.heartBeat;
        uint256 timeSinceLastUpdate = block.timestamp - timestamp;
        if (timeSinceLastUpdate > heartbeat) revert STATE_StalePrice(address(asset), timeSinceLastUpdate, heartbeat);
    }
}
