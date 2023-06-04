// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { IBalancerPool } from "src/interfaces/external/IBalancerPool.sol";
import { BalancerPoolExtension, PriceRouter, ERC20, Math, IVault, IERC20 } from "./BalancerPoolExtension.sol";

/**
 * @title Sommelier Price Router Balancer Stable Pool Extension
 * @notice Allows the Price Router to price Balancer Stable pool BPTs.
 * @author crispymangoes
 */
contract BalancerStablePoolExtension is BalancerPoolExtension {
    using Math for uint256;

    /**
     * @notice Atleast one of the pools underlying tokens is not supported by the Price Router.
     */
    error BalancerStablePoolExtension__PoolTokensMustBeSupported(address unsupportedAsset);

    /**
     * @notice Failed to find a minimum price for the pool tokens.
     */
    error BalancerStablePoolExtension__MinimumPriceNotFound();

    constructor(PriceRouter _priceRouter, IVault _balancerVault) BalancerPoolExtension(_priceRouter, _balancerVault) {}

    /**
     * @notice Extension storage
     * @param poolId the pool id of the BPT being priced
     * @param poolDecimals the decimals of the BPT being priced
     * @param underlyings the ERC20 underlying asset for each constituent in the pool
     */
    struct ExtensionStorage {
        bytes32 poolId;
        uint8 poolDecimals;
        ERC20[8] underlyings;
    }

    /**
     * @notice Balancer Stable Pool Extension Storage
     */
    mapping(ERC20 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset the BPT token
     */
    function setupSource(ERC20 asset, bytes memory _storage) external override onlyPriceRouter {
        IBalancerPool pool = IBalancerPool(address(asset));
        ExtensionStorage memory stor = abi.decode(_storage, (ExtensionStorage));

        // Grab the poolId and decimals.
        stor.poolId = pool.getPoolId();
        stor.poolDecimals = pool.decimals();

        // Make sure we can price all underlying tokens.
        for (uint256 i; i < stor.underlyings.length; ++i) {
            // Break when a zero address is found.
            if (address(stor.underlyings[i]) == address(0)) break;
            if (!priceRouter.isSupported(stor.underlyings[i]))
                revert BalancerStablePoolExtension__PoolTokensMustBeSupported(address(stor.underlyings[i]));
        }

        // Save values in extension storage.
        extensionStorage[asset] = stor;
    }

    /**
     * @notice Called during pricing operations.
     * @param asset the BPT token
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256) {
        _ensureNotInVaultContext(balancerVault);
        IBalancerPool pool = IBalancerPool(address(asset));

        // Read extension storage and grab pool tokens
        ExtensionStorage memory stor = extensionStorage[asset];

        // Find the minimum price of all the pool tokens.
        uint256 minPrice = type(uint256).max;
        for (uint256 i; i < stor.underlyings.length; ++i) {
            // Break when a zero address is found.
            if (address(stor.underlyings[i]) == address(0)) break;
            uint256 price = priceRouter.getPriceInUSD(stor.underlyings[i]);
            if (price < minPrice) minPrice = price;
        }

        if (minPrice == type(uint256).max) revert BalancerStablePoolExtension__MinimumPriceNotFound();

        uint256 priceBpt = minPrice.mulDivDown(pool.getRate(), 10 ** stor.poolDecimals);
        return priceBpt;
    }
}
