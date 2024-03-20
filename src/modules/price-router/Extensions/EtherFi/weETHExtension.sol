// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Extension, PriceRouter, ERC20, Math} from "src/modules/price-router/Extensions/Extension.sol";
import {IRateProvider} from "src/interfaces/external/EtherFi/IRateProvider.sol";

contract weEthExtension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    /**
     * @notice Attempted to add weETH support when wETH is not supported.
     */
    error weEthExtension__WETH_NOT_SUPPORTED();

    /**
     * @notice Attempted to use this extension to price something other than weETH.
     */
    error weEthExtension__ASSET_NOT_WEETH();

    /**
     * @notice Ethereum mainnet wETH.
     */
    ERC20 internal constant wETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /**
     * @notice Ethereum mainnet weETH.
     */
    ERC20 internal constant weETH = ERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset weETH
     * @dev bytes input is not used
     */
    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        if (address(asset) != address(weETH)) revert weEthExtension__ASSET_NOT_WEETH();
        if (!priceRouter.isSupported(wETH)) revert weEthExtension__WETH_NOT_SUPPORTED();
    }

    /**
     * @notice Called during pricing operations.
     * @dev asset not used since setup function confirms `asset` is weETH.
     * @return price of weETH in USD
     */
    function getPriceInUSD(ERC20) external view override returns (uint256) {
        return
            priceRouter.getPriceInUSD(wETH).mulDivDown(IRateProvider(address(weETH)).getRate(), 10 ** weETH.decimals());
    }
}
