// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { ISTETH } from "src/interfaces/external/ISTETH.sol";

/**
 * @title Sommelier Price Router wstEth Extension
 * @notice Allows the Price Router to price wstEth.
 * @author crispymangoes
 */
contract WstEthExtension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    /**
     * @notice Attempted to add wstEth support when stEth is not supported.
     */
    error WstEthExtension__STETH_NOT_SUPPORTED();

    /**
     * @notice Attempted to use this extension to price something other than wstEth.
     */
    error WstEthExtension__ASSET_NOT_WSTETH();

    /**
     * @notice Ethereum mainnet stEth.
     */
    ISTETH public stEth = ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    /**
     * @notice Ethereum mainnet wstEth.
     */
    address public wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset wstEth
     * @dev bytes input is not used
     */
    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        if (address(asset) != wstEth) revert WstEthExtension__ASSET_NOT_WSTETH();
        if (!priceRouter.isSupported(ERC20(address(stEth)))) revert WstEthExtension__STETH_NOT_SUPPORTED();
    }

    /**
     * @notice Called during pricing operations.
     * @dev asset not used since setup function confirms `asset` is wstEth.
     */
    function getPriceInUSD(ERC20) external view override returns (uint256) {
        return
            stEth.getPooledEthByShares(1e18).mulDivDown(
                priceRouter.getPriceInUSD(ERC20(address(stEth))),
                10 ** ERC20(wstEth).decimals()
            );
    }
}
