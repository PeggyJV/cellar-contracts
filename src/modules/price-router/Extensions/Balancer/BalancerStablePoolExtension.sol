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
    error BalancerStablePoolExtension__PoolTokensMustBeSupported();

    /**
     * @notice Failed to find a minimum price for the pool tokens.
     */
    error BalancerStablePoolExtension__MinimumPriceNotFound();

    constructor(PriceRouter _priceRouter, IVault _balancerVault) BalancerPoolExtension(_priceRouter, _balancerVault) {}

    // TODO so we could store the pools tokens in this contract to reduce external calls
    // but do the pool tokens change?
    /**
     * @notice Extension storage
     * @param poolId the pool id of the BPT being priced
     * @param poolDecimals the decimals of the BPT being priced
     */
    struct ExtensionStorage {
        bytes32 poolId;
        uint8 poolDecimals;
    }

    /**
     * @notice Balancer Stable Pool Extension Storage
     */
    mapping(ERC20 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset the BPT token
     * @dev bytes input is not used
     */
    function setupSource(ERC20 asset, bytes memory) external override onlyPriceRouter {
        IBalancerPool pool = IBalancerPool(address(asset));

        // Grab the poolId and tokens.
        bytes32 poolId = pool.getPoolId();
        (IERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);

        // Make sure we can price all underlying tokens.
        for (uint256 i; i < tokens.length; ++i) {
            // TODO is this gucci?
            if (address(tokens[i]) == address(asset)) continue;
            if (!priceRouter.isSupported(ERC20(address(tokens[i]))))
                revert BalancerStablePoolExtension__PoolTokensMustBeSupported();
        }

        // Save values in extension storage.
        extensionStorage[asset].poolId = poolId;
        extensionStorage[asset].poolDecimals = pool.decimals();
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
        (IERC20[] memory tokens, , ) = balancerVault.getPoolTokens(stor.poolId);

        // Find the minimum price of all the pool tokens.
        uint256 minPrice = type(uint256).max;
        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) == address(asset)) continue;
            uint256 price = priceRouter.getPriceInUSD(ERC20(address(tokens[i])));
            if (price < minPrice) minPrice = price;
        }

        if (minPrice == type(uint256).max) revert BalancerStablePoolExtension__MinimumPriceNotFound();

        uint256 priceBpt = minPrice.mulDivDown(pool.getRate(), 10 ** stor.poolDecimals);
        return priceBpt;
    }
}
