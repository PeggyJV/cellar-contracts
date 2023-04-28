// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

interface STETH {
    function getPooledEthByShares(uint256 shares) external view returns (uint256);

    function decimals() external view returns (uint8);
}

contract WstEthExtension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    error WstEthExtension__STETH_NOT_SUPPORTED();
    error WstEthExtension__ASSET_NOT_WSTETH();

    STETH public stEth = STETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    address public wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        if (address(asset) != wstEth) revert WstEthExtension__ASSET_NOT_WSTETH();
        if (!priceRouter.isSupported(ERC20(address(stEth)))) revert WstEthExtension__STETH_NOT_SUPPORTED();
    }

    // TODO nitpick think this needs to divide by wsteth decimals not steth(eventhough they are the same)
    function getPriceInUSD(ERC20) external view override returns (uint256) {
        return
            stEth.getPooledEthByShares(1e18).mulDivDown(
                priceRouter.getPriceInUSD(ERC20(address(stEth))),
                10 ** stEth.decimals()
            );
    }
}
