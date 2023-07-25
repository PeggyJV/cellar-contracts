// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { ISTETH } from "src/interfaces/external/ISTETH.sol";

/**
 * @title Sommelier Price Router wstEth Extension
 * @notice Allows the Price Router to price wstEth.
 * @author crispymangoes
 */
contract StEthExtension is Extension {
    using Math for uint256;

    uint256 public immutable allowedDivergence;

    constructor(PriceRouter _priceRouter, uint256 _allowedDivergence) Extension(_priceRouter) {
        allowedDivergence = _allowedDivergence;
    }

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

    address public curveNgPool;
    address public uniV3Pool;
    address public chainlinkDataFeed;

    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        if (address(asset) != address(stEth)) revert WstEthExtension__ASSET_NOT_WSTETH();
        // Make sure we can get prices from above sources
    }

    function getPriceInUSD(ERC20) external view override returns (uint256) {
        // Get Chainlink stETH - ETH price
        // Get price from Curve EMA
        // Compare the two, if they are within allowed divergence, use curve ema, otherwise use chainlink value.
        // Convert answer into USD.
    }
}
