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

    /**
     * @notice Address Curve uses to represent native asset.
     */
    address public constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @notice Decimals curve uses for their pools.
     */
    uint8 public immutable curveDecimals;

    /**
     * @notice Native Wrapper address.
     */
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
     * @notice Curve pool is not supported by extension.
     */
    error Curve2PoolExtension_POOL_NOT_SUPPORTED();

    /**
     * @notice Extension storage
     * @param pool address of the curve pool to use as an oracle
     * @param underlyingOrConstituent0 the underlying or constituent for coins 0
     * @param underlyingOrConstituent1 the underlying or constituent for coins 1
     * @param divideRate0 bool indicating whether or not we need to divide out the pool stored rate
     * @param divideRate1 bool indicating whether or not we need to divide out the pool stored rate
     * @param isCorrelated bool indicating whether the pool has correlated assets or not
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
        ExtensionStorage memory stor = abi.decode(_storage, (ExtensionStorage));
        CurvePool pool = CurvePool(stor.pool);

        // Figure out how long `coins` is.
        uint256 coinsLength;
        while (true) {
            try pool.coins(coinsLength) {
                coinsLength++;
            } catch {
                break;
            }
        }

        // Revert if we are not dealing with a 2 coin pool.
        if (coinsLength > 2) revert Curve2PoolExtension_POOL_NOT_SUPPORTED();

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
                revert Curve2PoolExtension_POOL_NOT_SUPPORTED();
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

            // Handle rates if needed.
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
        } else {
            price = pool.lp_price().mulDivDown(
                priceRouter.getPriceInUSD(ERC20(stor.underlyingOrConstituent0)),
                10 ** curveDecimals
            );
        }
    }

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
