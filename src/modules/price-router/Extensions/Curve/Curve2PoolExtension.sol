// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { CurvePool } from "src/interfaces/external/Curve/CurvePool.sol";

/**
 * @title Sommelier Price Router Curve 2Pool Extension
 * @notice Allows the Price Router to price Curve LP with 2 underlying coins.
 * @author crispymangoes
 */
contract Curve2PoolExtension is Extension {
    using Math for uint256;

    address public constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint8 public immutable curveDecimals;

    ERC20 public immutable WETH;

    constructor(PriceRouter _priceRouter, address _weth, uint8 _curveDecimals) Extension(_priceRouter) {
        WETH = ERC20(_weth);
        curveDecimals = _curveDecimals;
    }

    /**
     * @notice Curve pool coins[0] is not supported by price router.
     */
    error Curve2PoolExtension_ASSET_NOT_SUPPORTED();

    /**
     * @notice Extension storage
     * @param pool address of the curve pool to use as an oracle
     * EIN QUESTION - params don't match up
     * @param index what index to use when querying the price
     * @param needIndex bool indicating whether or not price_oracle should or should not be called with an index variable
     */
    struct ExtensionStorage {
        address pool;
        address underlyingOrConstituent0;
        address underlyingOrConstituent1;
        bool divideRate0; // If we only have the market price of the underlying, and there is a rate with the underlying, then divide out the rate
        bool divideRate1; // If we only new the safe price of sDAI, then we need to divide out the rate stored in the curve pool
        bool isCorrelated; // but if we know the safe market price of DAI then we can just use that.
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
        // From what I can tell there are 2 types of curve 2Pools.
        // 1) uncorrelated coins, call pool.lp_price() and multiply by coins[0] price
        // 2) correlated coins, query both underlyings prices from price router, find the min price, and multiply by virtual price.
        ExtensionStorage memory stor = abi.decode(_storage, (ExtensionStorage));
        CurvePool pool = CurvePool(stor.pool);
        uint256 coinsLength;
        while (true) {
            try pool.coins(coinsLength) {
                coinsLength++;
            } catch {
                break;
            }
        }

        if (coinsLength > 2) revert("3pool not supported");

        // Make sure underlyingOrConstituent0 is supported.
        if (!priceRouter.isSupported(ERC20(stor.underlyingOrConstituent0)))
            revert Curve2PoolExtension_ASSET_NOT_SUPPORTED();

        if (stor.isCorrelated) {
            // pool.lp_price() not available
            // Make sure coins[1] is also supported.
            if (!priceRouter.isSupported(ERC20(stor.underlyingOrConstituent1)))
                revert Curve2PoolExtension_ASSET_NOT_SUPPORTED();
        } else {
            // Make sure pool.lp_price() is available.
            try pool.lp_price() {} catch {
                revert("Unsupported pool");
            }
        }

        extensionStorage[asset] = stor;
    }

    /**
     * @notice Called during pricing operations.
     * @param asset the asset to price using the Curve EMA oracle
     */
    function getPriceInUSD(ERC20 asset) external view override returns (uint256 price) {
        ExtensionStorage memory stor = extensionStorage[asset];
        CurvePool pool = CurvePool(stor.pool);

        if (stor.isCorrelated) {
            // Find the minimum price of coins.
            uint256 price0 = priceRouter.getPriceInUSD(ERC20(stor.underlyingOrConstituent0));
            uint256 price1 = priceRouter.getPriceInUSD(ERC20(stor.underlyingOrConstituent1));
            if (stor.divideRate0 || stor.divideRate1) {
                uint256[2] memory rates = pool.stored_rates();
                if (stor.divideRate0) {
                    price0 = price0.mulDivDown(10 ** curveDecimals, rates[0]);
                }
                if (stor.divideRate1) {
                    price1 = price1.mulDivDown(10 ** curveDecimals, rates[1]);
                }
            }
            uint256 minPrice = price0 < price1 ? price0 : price1;
            price = minPrice.mulDivDown(pool.get_virtual_price(), 10 ** curveDecimals);
            // TODO add in new underlying or constituent logic here with rates.
        } else {
            // TODO I wonder if rates would also need to come up here, like if this new pool ever gave the lp_price without adjusting for the rate, then we would need to?
            // TODO ^^^ I dont think this makes sense cuz the point of it acconting for the rate is to keep the liquidity concentrated at that rate
            // but you can only do that with correlated pairs.
            price = pool.lp_price().mulDivDown(priceRouter.getPriceInUSD(getCoins(pool, 0)), 10 ** curveDecimals);
        }
    }
    /**
     * There are stable-swap invar pools, cryptoPools (2 volatile assets), tricrypto pools (3 volatile assets). Within these categories are subsets: plain pools and meta-pools. Secondary ones are lending pools, ERC4626 Pools, rebase asset pools.
     * The API for price oracles consist of several getters, ofc there must be guardrails to protect against any risk vectors originating from using curve price oracles.
     * 
     */

    /**
     * @notice Helper functions to get the index of coins.
     * @dev Handles cases where Curve Pool uses ETH instead of WETH.
     */
    function getCoins(CurvePool pool, uint256 index) public view returns (ERC20) {
        ERC20 coin = ERC20(pool.coins(index));
        // Handle Curve Pools that use Curve ETH instead of WETH.
        return address(coin) == CURVE_ETH ? WETH : coin;
    }
}
