// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC4626.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Math } from "src/utils/Math.sol";

abstract contract Extension {
    error Extension__OnlyPriceRouter();
    modifier onlyPriceRouter() {
        if (msg.sender != address(priceRouter)) revert Extension__OnlyPriceRouter();
        _;
    }

    PriceRouter public immutable priceRouter;

    constructor(PriceRouter _priceRouter) {
        priceRouter = _priceRouter;
    }

    // Only callable by pricerouter.
    function setupSource(ERC20 asset, bytes memory sourceData) external virtual;

    function getPriceInUSD(ERC20 asset) external view virtual returns (uint256);
}
