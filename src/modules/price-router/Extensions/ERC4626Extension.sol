// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";

/**
 * @title Sommelier Price Router ERC4626 Extension
 * @notice Allows the Price Router to price ERC4626 shares.
 * @author crispymangoes
 */
contract ERC4626Extension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    /**
     * @notice ERC4626.asset() is not supported in the price router.
     */
    error ERC4626Extension_ASSET_NOT_SUPPORTED();

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset the ERC4626 vault share to price
     */
    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        ERC4626 vault = ERC4626(address(asset));

        // Make sure price router supports Asset.
        if (!priceRouter.isSupported(vault.asset())) revert ERC4626Extension_ASSET_NOT_SUPPORTED();
    }

    /**
     * @notice Called during pricing operations.
     * @param asset the ERC4626 vault share to price
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256 price) {
        ERC4626 vault = ERC4626(address(asset));

        ERC20 vaultAsset = vault.asset();
        uint256 assetPrice = priceRouter.getPriceInUSD(vaultAsset);
        uint256 oneShare = 10 ** vault.decimals();
        price = assetPrice.mulDivDown(vault.previewRedeem(oneShare), 10 ** vaultAsset.decimals());
    }
}
