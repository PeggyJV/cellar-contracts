// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { CurvePool } from "src/interfaces/external/Curve/CurvePool.sol";

/**
 * @title Sommelier Price Router Curve EMA Extension
 * @notice Allows the Price Router to price assets using Curve EMA oracles.
 * @author crispymangoes
 */
contract CurveEMAExtension is Extension {
    using Math for uint256;

    address public constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint8 public immutable curveEMADecimals;

    ERC20 public immutable WETH;

    constructor(PriceRouter _priceRouter, address _weth, uint8 _curveEMADecimals) Extension(_priceRouter) {
        WETH = ERC20(_weth);
        curveEMADecimals = _curveEMADecimals;
    }

    /**
     * @notice Curve pool coins[0] is not supported by price router.
     */
    error CurveEMAExtension_ASSET_NOT_SUPPORTED();

    /**
     * @notice Extension storage
     * @param pool address of the curve pool to use as an oracle
     * @param index what index to use when querying the price
     * @param needIndex bool indicating whether or not price_oracle should or should not be called with an index variable
     * @param rateIndex what index to use when querying the stored_rate
     * @param handleRate bool indicating whether or not price_oracle needs to account for a rate
     */
    struct ExtensionStorage {
        address pool;
        uint8 index;
        bool needIndex;
        uint8 rateIndex;
        bool handleRate;
    }

    /**
     * @notice Curve EMA Extension Storage
     */
    mapping(ERC20 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param asset the ERC20 asset to price using a Curve EMA
     */
    function setupSource(ERC20 asset, bytes memory _storage) external override onlyPriceRouter {
        ExtensionStorage memory stor = abi.decode(_storage, (ExtensionStorage));
        CurvePool pool = CurvePool(stor.pool);
        ERC20 coins0 = getCoinsZero(pool);

        if (!priceRouter.isSupported(coins0))
            // Insure curve pool coins[0] is supported.
            revert CurveEMAExtension_ASSET_NOT_SUPPORTED();

        // Make sure we can query the price.
        getPriceFromCurvePool(pool, stor.index, stor.needIndex, stor.rateIndex, stor.handleRate);

        // Save extension storage.
        extensionStorage[asset] = stor;
    }

    /**
     * @notice Called during pricing operations.
     * @param asset the asset to price using the Curve EMA oracle
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256 price) {
        ExtensionStorage memory stor = extensionStorage[asset];
        CurvePool pool = CurvePool(stor.pool);

        ERC20 coins0 = getCoinsZero(pool);
        uint256 priceInAsset = getPriceFromCurvePool(pool, stor.index, stor.needIndex, stor.rateIndex, stor.handleRate);

        uint256 assetPrice = priceRouter.getPriceInUSD(coins0);
        price = assetPrice.mulDivDown(priceInAsset, 10 ** curveEMADecimals);
    }

    /**
     * @notice Helper functions to get the zero index of coins.
     * @dev Handles cases where Curve Pool uses ETH instead of WETH.
     */
    function getCoinsZero(CurvePool pool) public view returns (ERC20) {
        ERC20 coins0 = ERC20(pool.coins(0));
        // Handle Curve Pools that use Curve ETH instead of WETH.
        return address(coins0) == CURVE_ETH ? WETH : coins0;
    }

    // TODO this code needs to change so that is can optionally handle tokens with rates, and basically take the price_oracle value and multiply by the rate.
    // Examples are ETHx, sDAI, sFRAX.
    /**
     * @notice Helper function to get the price of an asset using a Curve EMA Oracle.
     * There are plain pools, crypto pools (concentrated liquidity && non-correlated assets), 
     */
    function getPriceFromCurvePool(
        CurvePool pool,
        uint8 index,
        bool needIndex,
        uint8 rateIndex,
        bool handleRate
    ) public view returns (uint256 price) {
        price = needIndex ? pool.price_oracle(index) : pool.price_oracle();
        if (handleRate) price = price.mulDivDown(pool.stored_rates()[rateIndex], 10 ** curveEMADecimals);
    }
}
