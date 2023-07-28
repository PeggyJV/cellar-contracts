// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IBalancerPool } from "src/interfaces/external/IBalancerPool.sol";
import { IRateProvider } from "src/interfaces/external/IRateProvider.sol";
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

    /**
     * @notice Failed to get rate from rate provider.
     */
    error BalancerStablePoolExtension__RateProviderCallFailed();

    /**
     * @notice Rate provider decimals not provided.
     */
    error BalancerStablePoolExtension__RateProviderDecimalsNotProvided();

    constructor(PriceRouter _priceRouter, IVault _balancerVault) BalancerPoolExtension(_priceRouter, _balancerVault) {}

    /**
     * @notice Extension storage
     * @param poolId the pool id of the BPT being priced
     * @param poolDecimals the decimals of the BPT being priced
     * @param rateProviders array of rate providers for each constituent
     *        a zero address rate provider means we are using an underlying correlated to the
     *        pools virtual base.
     * @param underlyingOrConstituent the ERC20 underlying asset or the constituent in the pool
     * @dev Only use the underlying asset, if the underlying is correlated to the pools virtual base.
     */
    struct ExtensionStorage {
        bytes32 poolId;
        uint8 poolDecimals;
        uint8[8] rateProviderDecimals;
        address[8] rateProviders;
        ERC20[8] underlyingOrConstituent;
    }

    /**
     * @notice Balancer Stable Pool Extension Storage
     */
    mapping(ERC20 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset the BPT token
     * @param _storage the abi encoded ExtensionStorage.
     * @dev _storage will have its poolId, and poolDecimals over written, but
     *      rateProviderDecimals, rateProviders, and underlyingOrConstituent
     *      MUST be correct, providing wrong values will result in inaccurate pricing.
     */
    function setupSource(ERC20 asset, bytes memory _storage) external override onlyPriceRouter {
        IBalancerPool pool = IBalancerPool(address(asset));
        ExtensionStorage memory stor = abi.decode(_storage, (ExtensionStorage));

        // Grab the poolId and decimals.
        stor.poolId = pool.getPoolId();
        stor.poolDecimals = pool.decimals();

        // Make sure we can price all underlying tokens.
        for (uint256 i; i < stor.underlyingOrConstituent.length; ++i) {
            // Break when a zero address is found.
            if (address(stor.underlyingOrConstituent[i]) == address(0)) break;
            if (!priceRouter.isSupported(stor.underlyingOrConstituent[i]))
                revert BalancerStablePoolExtension__PoolTokensMustBeSupported(address(stor.underlyingOrConstituent[i]));
            if (stor.rateProviders[i] != address(0)) {
                // Make sure decimals were provided.
                if (stor.rateProviderDecimals[i] == 0)
                    revert BalancerStablePoolExtension__RateProviderDecimalsNotProvided();
                // Make sure we can call it and get a non zero value.
                uint256 rate = IRateProvider(stor.rateProviders[i]).getRate();
                if (rate == 0) revert BalancerStablePoolExtension__RateProviderCallFailed();
            }
        }

        // Save values in extension storage.
        extensionStorage[asset] = stor;
    }

    /**
     * @notice Called during pricing operations.
     * @param asset the BPT token
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256) {
        ensureNotInVaultContext(balancerVault);
        IBalancerPool pool = IBalancerPool(address(asset));

        // Read extension storage and grab pool tokens
        ExtensionStorage memory stor = extensionStorage[asset];

        // Find the minimum price of all the pool tokens.
        uint256 minPrice = type(uint256).max;
        for (uint256 i; i < stor.underlyingOrConstituent.length; ++i) {
            // Break when a zero address is found.
            if (address(stor.underlyingOrConstituent[i]) == address(0)) break;
            uint256 price = priceRouter.getPriceInUSD(stor.underlyingOrConstituent[i]);
            if (stor.rateProviders[i] != address(0)) {
                uint256 rate = IRateProvider(stor.rateProviders[i]).getRate();
                price = price.mulDivDown(10 ** stor.rateProviderDecimals[i], rate);
            }
            if (price < minPrice) minPrice = price;
        }

        if (minPrice == type(uint256).max) revert BalancerStablePoolExtension__MinimumPriceNotFound();

        uint256 priceBpt = minPrice.mulDivDown(pool.getRate(), 10 ** stor.poolDecimals);
        return priceBpt;
    }
}
