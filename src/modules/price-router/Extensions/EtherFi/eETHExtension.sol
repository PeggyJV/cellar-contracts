// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IRateProvider } from "src/interfaces/external/EtherFi/IRateProvider.sol";

/**
 * @title Sommelier Price Router eETH Extension
 * @notice Allows the Price Router to price eETH.
 * @author 0xEinCodes
 */
contract eEthExtension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    /**
     * @notice Attempted to add wstEth support when stEth is not supported.
     */
    error eEthExtension__WEETH_NOT_SUPPORTED();

    /**
     * @notice Attempted to use this extension to price something other than wstEth.
     */
    error eEthExtension__ASSET_NOT_EETH();

    /**
     * @notice Ethereum mainnet eETH.
     */
    address public eETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;

    /**
     * @notice Ethereum mainnet weETH.
     */
    address public weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset eETH
     * @dev bytes input is not used
     */
    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        if (address(asset) != eETH) revert eEthExtension__ASSET_NOT_EETH();
        if (!priceRouter.isSupported(ERC20(address(weETH)))) revert eEthExtension__WEETH_NOT_SUPPORTED();
    }

    /**
     * @notice Called during pricing operations.
     * @dev asset not used since setup function confirms `asset` is weETH.
     * @return price of eETH in USD [USD/eETH]
     * TODO - confirm that units are [weETH / eETH] for `getRate()`
     */
    function getPriceInUSD(ERC20) external view override returns (uint256) {
        // get price: [USD/eETH] =  [weETH / eETH] * [USD/weETH]
        return
            IRateProvider(weETH).getRate().mulDivDown(
                priceRouter.getPriceInUSD(ERC20(weETH)),
                10 ** ERC20(weETH).decimals()
            );
    }
}
