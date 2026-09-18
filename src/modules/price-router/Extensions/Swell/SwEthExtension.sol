// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Extension, PriceRouter, ERC20, Math} from "src/modules/price-router/Extensions/Extension.sol";
import {IRateProvider} from "src/interfaces/external/EtherFi/IRateProvider.sol";

/**
 * @title Sommelier Price Router swETH Extension
 * @notice Allows the Price Router to price swETH in USD from swETH's own exchange rate.
 * @dev A line-for-line derivation of the audited `weEthExtension`, with weETH replaced by
 *      swETH. swETH exposes the same `getRate()` (the IRateProvider interface), returning the
 *      ETH value of one swETH. Replaces the abandoned Redstone swETH adapter; Chainlink has no
 *      swETH feed and on-chain swETH liquidity is too thin for a TWAP.
 */
contract SwEthExtension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    /**
     * @notice Attempted to add swETH support when wETH is not supported.
     */
    error SwEthExtension__WETH_NOT_SUPPORTED();

    /**
     * @notice Attempted to use this extension to price something other than swETH.
     */
    error SwEthExtension__ASSET_NOT_SWETH();

    /**
     * @notice Ethereum mainnet wETH.
     */
    ERC20 internal constant wETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /**
     * @notice Ethereum mainnet swETH.
     */
    ERC20 internal constant swETH = ERC20(0xf951E335afb289353dc249e82926178EaC7DEd78);

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset swETH
     * @dev bytes input is not used
     */
    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        if (address(asset) != address(swETH)) revert SwEthExtension__ASSET_NOT_SWETH();
        if (!priceRouter.isSupported(wETH)) revert SwEthExtension__WETH_NOT_SUPPORTED();
    }

    /**
     * @notice Called during pricing operations.
     * @dev asset not used since setup function confirms `asset` is swETH.
     * @return price of swETH in USD
     */
    function getPriceInUSD(ERC20) external view override returns (uint256) {
        return
            priceRouter.getPriceInUSD(wETH).mulDivDown(IRateProvider(address(swETH)).getRate(), 10 ** swETH.decimals());
    }
}
