// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IRateProvider } from "src/interfaces/external/EtherFi/IRateProvider.sol";

/**
 * @title Sommelier Price Router eETH Extension.
 * @notice Allows the Price Router to price eETH.
 * @author 0xEinCodes
 */
contract eEthExtension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    /**
     * @notice Attempted to add eETH support when weETH is not supported.
     */
    error eEthExtension__WEETH_NOT_SUPPORTED();

    /**
     * @notice Attempted to use this extension to price something other than eETH.
     */
    error eEthExtension__ASSET_NOT_EETH();

    /**
     * @notice Ethereum mainnet eETH.
     */
    ERC20 internal constant eETH = ERC20(0x35fA164735182de50811E8e2E824cFb9B6118ac2);

    /**
     * @notice Ethereum mainnet weETH.
     */
    ERC20 internal constant weETH = ERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset eETH
     * @dev bytes input is not used
     */
    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        if (address(asset) != address(eETH)) revert eEthExtension__ASSET_NOT_EETH();
        if (!priceRouter.isSupported(weETH)) revert eEthExtension__WEETH_NOT_SUPPORTED();
    }

    /**
     * @notice Called during pricing operations.
     * @dev asset not used since setup function confirms `asset` is weETH.
     * @return price of eETH in USD [USD/eETH]
     */
    function getPriceInUSD(ERC20) external view override returns (uint256) {
        return
            priceRouter.getPriceInUSD(weETH).mulDivDown(
                10 ** weETH.decimals(),
                IRateProvider(address(weETH)).getRate()
            );
    }
}
