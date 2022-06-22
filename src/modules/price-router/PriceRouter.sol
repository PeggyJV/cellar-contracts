// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ChainlinkPriceFeedAdaptor } from "src/modules/price-router/adaptors/ChainlinkPriceFeedAdaptor.sol";
import { IPriceFeedAdaptor } from "src/modules/price-router/adaptors/IPriceFeedAdaptor.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";

//TODO convert from WBTC to BTC first
//TODO add min and max logic into chainlink adaptor
contract PriceRouter is Ownable, ChainlinkPriceFeedAdaptor {
    using SafeTransferLib for ERC20;

    //in terms of 8 decimal USD
    //determined by interfacing with adaptors
    struct PricingInformation {
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
        bool assetSupported;
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
    constructor(FeedRegistryInterface _feedRegistry) ChainlinkPriceFeedAdaptor(_feedRegistry) {}

    // ======================================= Adaptor OPERATIONS =======================================

    function addAsset(
        address baseAsset,
        address adaptor,
        uint128 min,
        uint128 max,
        uint96 heartbeat,
        address remap
    ) external onlyOwner {
        require(baseAsset != address(0), "Invalid baseAsset");

        //first cache min/max if not provided
        if (min == 0 || max == 0) {
            //need to get the price range
            uint128 adaptorMin;
            uint128 adaptorMax;
            address asset = remap == address(0) ? baseAsset : remap;
            if (adaptor == address(0)) {
                //using this contract
                (adaptorMin, adaptorMax) = getPriceRange(asset);
            } else {
                (adaptorMin, adaptorMax) = IPriceFeedAdaptor(adaptor).getPriceRange(asset);
            }
            min = min == 0 ? adaptorMin : min;
            max = max == 0 ? adaptorMax : max;
        }

        //if heartbeat is 0 use default
        heartbeat = heartbeat == 0 ? defaultHeartBeat : heartbeat;

        assetInformation[baseAsset] = AssetInformation({
            assetMin: min,
            assetMax: max,
            adaptor: adaptor,
            heartBeat: heartbeat,
            remap: remap,
            assetSupported: true
        });
    }

    function changeDefaultAdaptor(address _default) external onlyOwner {
        defaultAdaptor = _default;
    }

    ///@dev allows owner to stop all pricing calls to baseAsset, can be undone by calling addAsset again
    function stopSupportForAsset(address baseAsset) external onlyOwner {
        assetInformation[baseAsset].assetSupported = false;
    }

    /**
     * @dev returns pricing information for baseAsset in terms of USD
     */
    function safePrice(address baseAsset) public view returns (uint256 price, uint256 timestamp) {
        //check baseAsset to adaptor
        AssetInformation storage storedInfo = assetInformation[baseAsset];
        require(storedInfo.assetSupported, "baseAsset is not supported");

        baseAsset = storedInfo.remap == address(0) ? baseAsset : storedInfo.remap;
        if (storedInfo.adaptor == address(0)) {
            (price, timestamp) = getPricingInformation(baseAsset);
        } else {
            (price, timestamp) = IPriceFeedAdaptor(storedInfo.adaptor).getPricingInformation(baseAsset);
        }

        require(price >= storedInfo.assetMin, "Asset price below min price");
        require(price <= storedInfo.assetMax, "Asset price above max price");
        require(block.timestamp - timestamp < storedInfo.heartBeat, "Stale price");
    }

    function getPriceInUSD(address baseAsset) public view returns (uint256 price) {
        (price, ) = safePrice(baseAsset);
    }

    function getAssetRange(address baseAsset) public view returns (uint256 min, uint256 max) {
        AssetInformation storage info = assetInformation[baseAsset];

        min = info.assetMin;
        max = info.assetMax;
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

    ///@dev could optimize by checking is quote is ETH, and if so just get the pricing info using ETH, but then we'd need to store min's and max's in ETH
    /// but then the ETH/USD min and max would be changing constantly relative to eachother
    function getExchangeRate(address baseAsset, address quoteAsset) public view returns (uint256 exchangeRate) {
        uint256 baseUSD = getPriceInUSD(baseAsset);
        uint256 quoteUSD = getPriceInUSD(quoteAsset);

        //returns quote per base
        exchangeRate = (10**ERC20(quoteAsset).decimals() * baseUSD) / quoteUSD;

        //1 of the base asset is worth exchangeRate amount of quote asset
    }

    //TODO a view funciton which indicates if a price is valid if its within the min and max, and the heartbeat is reasonable
}
