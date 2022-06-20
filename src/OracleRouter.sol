// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ChainlinkPriceFeedAdaptor } from "./ChainlinkPriceFeedAdaptor.sol";
import { BaseAdaptor } from "./BaseAdaptor.sol";

//TODO add some methof that reverts if an asset is black listed?
contract OracleRouter is Ownable {
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

    // ======================================= OWNER OPERATIONS =======================================

    function addAsset(
        address baseAsset,
        address adaptor,
        uint128 min,
        uint128 max,
        uint96 heartbeat
    ) external onlyOwner {
        //should call the getPricingInformation on the adaptor to confirm it meets standards
        BaseAdaptor(adaptor).getPricingInformation(baseAsset);

        assetInformation[baseAsset] = AssetInformation({
            assetMin: min,
            assetMax: max,
            adaptor: adaptor,
            heartBeat: heartbeat == 0 ? defaultHeartBeat : heartbeat //TODO should this be left?
        });
    }

    function changeDefaultAdaptor(address _default) external onlyOwner {
        defaultAdaptor = _default;
    }

    // ======================================= PRICING OPERATIONS =======================================

    //TODO if the asset isn't found in the deafult adaptor should this revert? If so probs want to make sure this is called whenever a cellars assets are changed to confirm we have pricing info for them!
    /**
     * @dev returns pricing information for baseAsset in terms of USD
     */
    function getPricingInformation(address baseAsset) public view returns (PricingInformation memory info) {
        //check baseAsset to adaptor
        AssetInformation memory storedInfo = assetInformation[baseAsset];
        BaseAdaptor adaptor = storedInfo.adaptor == address(0)
            ? BaseAdaptor(defaultAdaptor)
            : BaseAdaptor(storedInfo.adaptor);
        info = adaptor.getPricingInformation(baseAsset);

        //update min and max price if values have been set in this contract
        info.minPrice = storedInfo.assetMin == 0 ? info.minPrice : storedInfo.assetMin;
        info.maxPrice = storedInfo.assetMax == 0 ? info.maxPrice : storedInfo.assetMin;
        //latestTimestamp, and price are already gucci
    }

    function getPriceInUSD(address baseAsset) external view returns (uint256 price) {
        PricingInformation memory info = getPricingInformation(baseAsset);

        price = info.price;
    }

    function getAssetRange(address baseAsset) external view returns (uint256 min, uint256 max) {
        PricingInformation memory info = getPricingInformation(baseAsset);

        min = info.minPrice;
        max = info.maxPrice;
    }
}
