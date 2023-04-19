// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC4626.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

interface IExtension {
    // Only callable by pricerouter.
    function setupSource(ERC20 asset, bytes memory sourceData) external;

    function getPriceInUSD(
        ERC20 asset,
        PriceRouter.PriceCache[PriceRouter.PRICE_CACHE_SIZE()] memory cache
    ) external view returns (uint256);
}
