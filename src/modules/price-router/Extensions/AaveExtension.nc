// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Extension, PriceRouter, ERC20 } from "src/modules/price-router/Extensions/Extension.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

contract AaveExtension is Extension {
    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    /**
     * @notice Aave Derivative Storage
     */
    mapping(ERC20 => ERC20) public getAaveDerivativeStorage;

    function setupSource(ERC20 asset, bytes memory sourceData) external override onlyPriceRouter {
        address aTokenAddress = abi.decode(sourceData, (address));
        IAaveToken aToken = IAaveToken(aTokenAddress);
        getAaveDerivativeStorage[asset] = ERC20(aToken.UNDERLYING_ASSET_ADDRESS());
    }

    // TODO this might need to return the cache
    function getPriceInUSD(ERC20 asset) external view override returns (uint256) {
        // TODO this needs to run its own price cache check code, and maybe it just returns an array of new prices it got
        return priceRouter.getPriceInUSD(asset);
    }
}
