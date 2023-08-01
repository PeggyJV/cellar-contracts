// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @title Sommelier Price Router Extension abstract contract.
 * @notice Provides shared logic between Extensions.
 * @author crispymangoes
 */
abstract contract Extension {
    /**
     * @notice Attempted to call a function only callable by the price router.
     */
    error Extension__OnlyPriceRouter();

    /**
     * @notice Prevents non price router contracts from calling a function.
     */
    modifier onlyPriceRouter() {
        if (msg.sender != address(priceRouter)) revert Extension__OnlyPriceRouter();
        _;
    }

    /**
     * @notice The Sommelier PriceRouter contract.
     */
    PriceRouter public immutable priceRouter;

    constructor(PriceRouter _priceRouter) {
        priceRouter = _priceRouter;
    }

    /**
     * @notice Setup function is called when an asset is added/edited.
     */
    function setupSource(ERC20 asset, bytes memory sourceData) external virtual;

    /**
     * @notice Returns the price of an asset in USD.
     */
    function getPriceInUSD(ERC20 asset) external view virtual returns (uint256);
}
