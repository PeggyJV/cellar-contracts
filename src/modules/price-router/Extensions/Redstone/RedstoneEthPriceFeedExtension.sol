// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

/**
 * @title Sommelier Price Router Redstone Classic Extension Eth
 * @notice Allows the Price Router to price assets using Redstone Classic oracles.
 * @author crispymangoes
 */
contract RedstoneEthPriceFeedExtension is Extension {
    using Math for uint256;
    ERC20 public immutable WETH;

    constructor(PriceRouter _priceRouter, address _weth) Extension(_priceRouter) {
        WETH = ERC20(_weth);
    }

    /**
     * @notice Redstone Classic price feed is stale.
     */
    error RedstoneEthPriceFeedExtension__STALE_PRICE();

    /**
     * @notice Redstone Classic price feed price is zero.
     */
    error RedstoneEthPriceFeedExtension__ZERO_PRICE();

    /**
     * @notice WETH is not supported in the price router.
     */
    error RedstoneEthPriceFeedExtension_WETH_NOT_SUPPORTED();

    /**
     * @notice Extension storage
     * @param dataFeedId the id of the datafeed to pull
     * @param heartbeat heartbeat in seconds
     *        - How often the price feed must be updated.
     *        - If timestamp of last pricefeed is updated was more than heartbeat seconds ago
     *          revert.
     * @param IRedstoneAdapter the Redstone classic price feed address
     */
    struct ExtensionStorage {
        bytes32 dataFeedId;
        uint24 heartbeat;
        IRedstoneAdapter redstoneAdapter;
    }

    /**
     * @notice Redstone PriceFeed Extension Storage
     */
    mapping(ERC20 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset the asset the redstoneAdapter in `_storage` can price
     * @param _storage the abi encoded ExtensionStorage
     */
    function setupSource(ERC20 asset, bytes memory _storage) external override onlyPriceRouter {
        // Make sure we can get a nonzero price using the provided extension storage data.
        ExtensionStorage memory stor = abi.decode(_storage, (ExtensionStorage));

        (, uint128 updatedAt) = stor.redstoneAdapter.getTimestampsFromLatestUpdate();

        uint256 timeSinceLastUpdate = block.timestamp - updatedAt;
        if (timeSinceLastUpdate > stor.heartbeat) revert RedstoneEthPriceFeedExtension__STALE_PRICE();

        uint256 price = stor.redstoneAdapter.getValueForDataFeed(stor.dataFeedId);

        if (price == 0) revert RedstoneEthPriceFeedExtension__ZERO_PRICE();

        // Make sure price router supports WETH.
        if (!priceRouter.isSupported(WETH)) revert RedstoneEthPriceFeedExtension_WETH_NOT_SUPPORTED();

        extensionStorage[asset] = stor;
    }

    /**
     * @notice Called during pricing operations.
     * @param asset the ERC20 asset to price using Redstone Classic Oracle
     * @dev Uses Redstone Classic Price Feed to price `asset`.
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256) {
        ExtensionStorage memory stor = extensionStorage[asset];
        (, uint128 updatedAt) = stor.redstoneAdapter.getTimestampsFromLatestUpdate();

        uint256 timeSinceLastUpdate = block.timestamp - updatedAt;
        if (timeSinceLastUpdate > stor.heartbeat) revert RedstoneEthPriceFeedExtension__STALE_PRICE();

        uint256 price = stor.redstoneAdapter.getValueForDataFeed(stor.dataFeedId);
        if (price == 0) revert RedstoneEthPriceFeedExtension__ZERO_PRICE();

        // ETH price is given in 8 decimals, scale it up by 10 decimals,
        // so it has the same decimals as WETH.
        price = price.changeDecimals(8, 18); // 18 being how many decimals WETH has.

        // Convert price from ETH to USD.
        uint256 ethPrice = priceRouter.getPriceInUSD(WETH);
        price = price.mulDivDown(ethPrice, 1e18);

        return price;
    }
}
