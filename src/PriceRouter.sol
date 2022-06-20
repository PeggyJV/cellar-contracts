// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { OracleRouter } from "./OracleRouter.sol";

contract PriceRouter {
    using SafeTransferLib for ERC20;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Oracle Router contract used to get where pricing information exists
     */
    OracleRouter public immutable oracleRouter;

    /**
     *
     */
    constructor(OracleRouter _oracleRouter) {
        //set up Oracle Router
        oracleRouter = _oracleRouter;
    }

    // ======================================= PRICING OPERATIONS =======================================

    function getValue(
        address[] memory baseAssets,
        uint256[] memory amounts,
        address quoteAsset
    ) external view returns (uint256 sumOfBaseAssetsInQuoteAsset) {
        require(baseAssets.length == amounts.length, "length mismatch");
        for (uint256 i = 0; i < baseAssets.length; i++) {
            sumOfBaseAssetsInQuoteAsset +=
                (amounts[i] * getExchangeRate(baseAssets[i], quoteAsset)) /
                10**ERC20(baseAssets[i]).decimals();
        }
    }

    //TODO returns values in USD with 8 decimals? Should we add a quote asset?
    function getAssetsRange(address[] memory baseAssets)
        external
        view
        returns (uint256[] memory min, uint256[] memory max)
    {
        min = new uint256[](baseAssets.length);
        max = new uint256[](baseAssets.length);

        for (uint256 i = 0; i < baseAssets.length; i++) {
            (min[i], max[i]) = getAssetRange(baseAssets[i]);
        }
    }

    function getAssetRange(address baseAsset) public view returns (uint256, uint256) {
        (uint256 min, uint256 max) = oracleRouter.getAssetRange(baseAsset);
        return (uint256(min), uint256(max));
    }

    function getExchangeRates(address[] memory baseAssets, address quoteAsset)
        external
        view
        returns (uint256[] memory exchangeRates)
    {
        exchangeRates = new uint256[](baseAssets.length);

        for (uint256 i = 0; i < baseAssets.length; i++) {
            exchangeRates[i] = getExchangeRate(baseAssets[i], quoteAsset);
        }
    }

    //TODO add in safety checks
    function getExchangeRate(address baseAsset, address quoteAsset) public view returns (uint256 exchangeRate) {
        uint256 baseUSD = oracleRouter.getPriceInUSD(baseAsset);
        uint256 quoteUSD = oracleRouter.getPriceInUSD(quoteAsset);

        //returns quote per base
        exchangeRate = (10**ERC20(quoteAsset).decimals() * baseUSD) / quoteUSD;

        //1 of the base asset is worth exchangeRate amount of quote asset
    }

    //TODO a view funciton which indicates if a price is valid if its within the min and max, and the heartbeat is reasonable
}
