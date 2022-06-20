// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BaseAdaptor } from "./BaseAdaptor.sol";

contract PriceRouter is Ownable {
    using SafeTransferLib for ERC20;

    //in terms of 8 decimal USD
    //determined by interfacing with adaptors
    struct PricingInformation {
        uint256 minPrice;
        uint256 maxPrice;
        uint256 price;
        uint256 lastTimestamp;
    }

    //storage
    struct AssetInformation {
        uint128 assetMin;
        uint128 assetMax;
        address adaptor; //this could replace assetToAdaptor
        uint96 heartBeat; //maximum allowed time to pass with no update
        address remap;
        //So for chainlink most heartbeats are 3600 seconds
    }

    /**
     * @notice Default Adaptor used if not set
     */
    address public defaultAdaptor;

    uint96 public defaultHeartBeat = 1 days;

    mapping(address => AssetInformation) public assetInformation;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     *
     */
    constructor(address _defaultAdaptor) {
        defaultAdaptor = _defaultAdaptor;
    }

    // ======================================= Adaptor OPERATIONS =======================================

    function addAsset(
        address baseAsset,
        address adaptor,
        uint128 min,
        uint128 max,
        uint96 heartbeat,
        address remap
    ) external onlyOwner {
        assetInformation[baseAsset] = AssetInformation({
            assetMin: min,
            assetMax: max,
            adaptor: adaptor,
            heartBeat: heartbeat,
            remap: remap
        });
    }

    function changeDefaultAdaptor(address _default) external onlyOwner {
        defaultAdaptor = _default;
    }

    //TODO if the asset isn't found in the deafult adaptor should this revert? If so probs want to make sure this is called whenever a cellars assets are changed to confirm we have pricing info for them!
    /**
     * @dev returns pricing information for baseAsset in terms of USD
     */
    function getPricingInformation(address baseAsset) public view returns (PricingInformation memory info) {
        //check baseAsset to adaptor
        AssetInformation storage storedInfo = assetInformation[baseAsset];
        BaseAdaptor adaptor = storedInfo.adaptor == address(0)
            ? BaseAdaptor(defaultAdaptor)
            : BaseAdaptor(storedInfo.adaptor);
        baseAsset = storedInfo.remap == address(0) ? baseAsset : storedInfo.remap;
        info = adaptor.getPricingInformation(baseAsset);

        //update min and max price if values have been set in this contract
        info.minPrice = storedInfo.assetMin == 0 ? info.minPrice : storedInfo.assetMin;
        info.maxPrice = storedInfo.assetMax == 0 ? info.maxPrice : storedInfo.assetMin;
        //latestTimestamp, and price are already gucci

        require(info.price >= info.minPrice, "Asset price below min price");
        require(info.price <= info.maxPrice, "Asset price above max price");
        uint96 heartbeat = storedInfo.heartBeat == 0 ? defaultHeartBeat : storedInfo.heartBeat;
        require(block.timestamp - info.lastTimestamp < heartbeat, "Stale price");
    }

    function getPriceInUSD(address baseAsset) public view returns (uint256 price) {
        PricingInformation memory info = getPricingInformation(baseAsset);

        price = info.price;
    }

    function getAssetRange(address baseAsset) public view returns (uint256 min, uint256 max) {
        PricingInformation memory info = getPricingInformation(baseAsset);

        min = info.minPrice;
        max = info.maxPrice;
    }

    // ======================================= PRICING OPERATIONS =======================================

    function getValue(
        address[] memory baseAssets,
        uint256[] memory amounts,
        address quoteAsset
    ) external view returns (uint256 sumOfBaseAssetsInQuoteAsset) {
        require(baseAssets.length == amounts.length, "length mismatch");
        for (uint256 i = 0; i < baseAssets.length; i++) {
            sumOfBaseAssetsInQuoteAsset +=
                (amounts[i] * getExchangeRate(baseAssets[i], quoteAsset)) /
                10**ERC20(baseAssets[i]).decimals();
        }
    }

    //TODO returns values in USD with 8 decimals? Should we add a quote asset?
    function getAssetsRange(address[] memory baseAssets)
        external
        view
        returns (uint256[] memory min, uint256[] memory max)
    {
        min = new uint256[](baseAssets.length);
        max = new uint256[](baseAssets.length);

        for (uint256 i = 0; i < baseAssets.length; i++) {
            (min[i], max[i]) = getAssetRange(baseAssets[i]);
        }
    }

    function getExchangeRates(address[] memory baseAssets, address quoteAsset)
        external
        view
        returns (uint256[] memory exchangeRates)
    {
        exchangeRates = new uint256[](baseAssets.length);

        for (uint256 i = 0; i < baseAssets.length; i++) {
            exchangeRates[i] = getExchangeRate(baseAssets[i], quoteAsset);
        }
    }

    //TODO add in safety checks
    function getExchangeRate(address baseAsset, address quoteAsset) public view returns (uint256 exchangeRate) {
        uint256 baseUSD = getPriceInUSD(baseAsset);
        uint256 quoteUSD = getPriceInUSD(quoteAsset);

        //returns quote per base
        exchangeRate = (10**ERC20(quoteAsset).decimals() * baseUSD) / quoteUSD;

        //1 of the base asset is worth exchangeRate amount of quote asset
    }

    //TODO a view funciton which indicates if a price is valid if its within the min and max, and the heartbeat is reasonable
}
