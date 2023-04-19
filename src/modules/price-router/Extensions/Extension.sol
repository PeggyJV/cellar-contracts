// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC4626.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Math } from "src/utils/Math.sol";

abstract contract Extension {
    uint8 public constant PRICE_CACHE_SIZE = 8;

    modifier onlyPriceRouter() {
        if (msg.sender != address(priceRouter)) revert("Only the price router can call this");
        _;
    }

    PriceRouter public immutable priceRouter;

    constructor(PriceRouter _priceRouter) {
        priceRouter = _priceRouter;
    }

    // Only callable by pricerouter.
    function setupSource(ERC20 asset, bytes memory sourceData) external virtual;

    function getPriceInUSD(
        ERC20 asset,
        PriceRouter.PriceCache[PRICE_CACHE_SIZE] memory cache
    ) external view virtual returns (uint256);
}
