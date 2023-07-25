// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar } from "src/base/Cellar.sol";
import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

/**
 * @title Sommelier Price Router wstEth Extension
 * @notice Allows the Price Router to price wstEth.
 * @author crispymangoes
 */
contract CellarExtension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    mapping(ERC20 => address) public extensionStorage;

    function setupSource(ERC20 asset, bytes memory data) external override onlyPriceRouter {
        ERC4626SharePriceOracle oracle = abi.decode(data, (ERC4626SharePriceOracle));

        Cellar target = Cellar(address(asset));
        if (address(oracle) == address(0)) {
            // Make sure previewRedeem works.
            target.previewRedeem(10 ** target.decimals());
        } else {
            if (address(target) != address(oracle.target())) revert("Wrong oracle");
            extensionStorage[asset] = address(oracle);
        }
    }

    function getPriceInUSD(ERC20 asset) external view override returns (uint256) {
        ERC4626SharePriceOracle oracle = ERC4626SharePriceOracle(extensionStorage[asset]);
        Cellar target = Cellar(address(asset));

        uint256 answer;
        if (address(oracle) == address(0)) {
            // Make sure previewRedeem works.
            answer = target.previewRedeem(10 ** target.decimals());
        } else {
            bool notSafeToUse;
            (answer, , notSafeToUse) = oracle.getLatest();
            if (notSafeToUse) revert("Oracle Revert");
        }

        // convert answer to USD.
        ERC20 targetAsset = target.asset();
        return answer.mulDivDown(priceRouter.getPriceInUSD(targetAsset), 10 ** targetAsset.decimals());
    }
}
