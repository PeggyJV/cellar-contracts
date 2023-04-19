// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { IExtension, PriceRouter, ERC20 } from "src/modules/price-router/Extensions/IExtension.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

contract AaveExtension is IExtension {
    PriceRouter public immutable priceRouter;

    constructor(PriceRouter _priceRouter) {
        priceRouter = _priceRouter;
    }

    /**
     * @notice Aave Derivative Storage
     */
    mapping(ERC20 => ERC20) public getAaveDerivativeStorage;

    function setupSource(ERC20 asset, bytes memory sourceData) external {
        if (msg.sender != priceRouter) revert("Only the price router can call this");

        address aTokenAddress = abi.decode(sourceData, (address));
        IAaveToken aToken = IAaveToken(aTokenAddress);
        getAaveDerivativeStorage[asset] = ERC20(aToken.UNDERLYING_ASSET_ADDRESS());
    }

    // TODO this might need to return the cache
    function getPriceInUSD(
        ERC20 asset,
        PriceRouter.PriceCache[PriceRouter.PRICE_CACHE_SIZE()] memory cache
    ) external view returns (uint256) {
        // TODO this needs to run its own price cache check code, and maybe it just returns an array of new prices it got
        return priceRouter.extensionGetPriceInUSD(asset, cache);
    }
}
