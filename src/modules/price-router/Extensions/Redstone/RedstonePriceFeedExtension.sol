// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20 } from "src/modules/price-router/Extensions/Extension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

/**
 * @title Sommelier Price Router Redstone Classic Extension
 * @notice Allows the Price Router to price assets using Redstone Classic oracles.
 * @author crispymangoes
 */
contract RedstonePriceFeedExtension is Extension {
    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    /**
     * @notice Redstone Classic price feed is stale.
     */
    error RedstonePriceFeedExtension__STALE_PRICE();

    /**
     * @notice Redstone Classic price feed price is zero.
     */
    error RedstonePriceFeedExtension__ZERO_PRICE();

    /**
     * @notice Extension storage
     * @param dataFeedId the id of the datafeed to pull
     * @param heartbeat heartbeat in seconds
     *        - How often the price feed must be updated.
     *        - If timestamp of last price feed is updated was more than heartbeat seconds ago
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
        if (timeSinceLastUpdate > stor.heartbeat) revert RedstonePriceFeedExtension__STALE_PRICE();

        uint256 price = stor.redstoneAdapter.getValueForDataFeed(stor.dataFeedId);

        if (price == 0) revert RedstonePriceFeedExtension__ZERO_PRICE();

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
        if (timeSinceLastUpdate > stor.heartbeat) revert RedstonePriceFeedExtension__STALE_PRICE();

        uint256 price = stor.redstoneAdapter.getValueForDataFeed(stor.dataFeedId);
        if (price == 0) revert RedstonePriceFeedExtension__ZERO_PRICE();
        return price;
    }
}
