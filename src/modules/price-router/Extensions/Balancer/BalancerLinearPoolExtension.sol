// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { IBalancerPool } from "src/interfaces/external/IBalancerPool.sol";
import { BalancerPoolExtension, PriceRouter, ERC20, Math, IVault, IERC20 } from "./BalancerPoolExtension.sol";

/**
 * @title Sommelier Price Router Balancer Linear Pool Extension
 * @notice Allows the Price Router to price Balancer Linear pool BPTs.
 * @author crispymangoes
 */
contract BalancerLinearPoolExtension is BalancerPoolExtension {
    using Math for uint256;

    /**
     * @notice The BPTs main token is not supported by the Price Router.
     */
    error BalancerLinearPoolExtension__MainTokenMustBeSupported();

    /**
     * @notice Extension storage
     * @param mainToken the BPTs main token
     * @param poolDecimals the decimals of the BPT being priced
     */
    struct ExtensionStorage {
        ERC20 mainToken;
        uint8 poolDecimals;
    }

    constructor(PriceRouter _priceRouter, IVault _balancerVault) BalancerPoolExtension(_priceRouter, _balancerVault) {}

    /**
     * @notice Balancer Linear Pool Extension Storage
     */
    mapping(ERC20 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset the BPT token
     * @dev bytes input is not used
     */
    function setupSource(ERC20 asset, bytes memory) external override onlyPriceRouter {
        IBalancerPool pool = IBalancerPool(address(asset));

        ERC20 mainToken = ERC20(pool.getMainToken());

        // Make sure we can price all underlying tokens.
        if (!priceRouter.isSupported(mainToken)) revert BalancerLinearPoolExtension__MainTokenMustBeSupported();

        // Save values in extension storage.
        extensionStorage[asset].mainToken = mainToken;
        extensionStorage[asset].poolDecimals = pool.decimals();
    }

    /**
     * @notice Called during pricing operations.
     * @param asset the BPT token
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256) {
        _ensureNotInVaultContext(balancerVault);
        IBalancerPool pool = IBalancerPool(address(asset));

        ExtensionStorage memory stor = extensionStorage[asset];

        uint256 priceBpt = priceRouter.getPriceInUSD(stor.mainToken).mulDivDown(
            pool.getRate(),
            10 ** stor.poolDecimals
        );
        return priceBpt;
    }
}
