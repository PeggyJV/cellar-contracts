// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Cellar, Registry, PriceRouter } from "src/base/Cellar.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { console } from "@forge-std/Test.sol";
import { INonfungiblePositionManager } from "src/interfaces/external/INonfungiblePositionManager.sol";
import { TickMath } from "src/interfaces/external/TickMath.sol";
import { Math as FullMath } from "src/utils/Math.sol";
import { FixedPoint96 } from "@uniswapV3C/libraries/FixedPoint96.sol";

/**
 * @title Uniswap V3 Adaptor
 * @notice Cellars make delegate call to this contract in order to interact with other Cellar contracts.
 * @author crispymangoes
 */

//TODO
/**
So I am thinking the best way to do this is to create a custom external contract that allows cellars to create UniV3 LP positions.
The adaptor data would have some ID or hash(maybe of the address of the two tokens they want to LP). then on adaptor calls SPs can call a function in this contract to send some of their tokens to be added
to liquidity 
This contract would need to track the cellars balanceOf and assets of, and do the conversion from NFT to underlying. I guess each cellar will need to pass in their position ID, then this contract would go okay, they have this NFT related to this position and then break down the underlying tokens and return the balance
 */
//balanceOf inspired by https://github.com/0xparashar/UniV3NFTOracle/blob/master/contracts/UniV3NFTOracle.sol
contract UniswapV3Adaptor is BaseAdaptor {
    using SafeERC20 for ERC20;
    using FullMath for uint256;

    /*
        adaptorData = abi.encode(token0, token1)
        adaptorStroage(written in registry) = abi.encode(uint256[] tokenIds)
    */

    //============================================ Global Functions ===========================================

    function positionManager() internal view returns (INonfungiblePositionManager) {
        return INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    }

    //If using delegate call then address(this) is wrong
    function getStorage() internal view returns (uint256[] memory) {
        Registry registry = Cellar(msg.sender).registry();
        bytes memory storageData = registry.getAdaptorStorage(
            msg.sender,
            keccak256(abi.encode(address(this), adaptorData))
        );

        return abi.decode(storageData, (uint256[]));
    }

    function writeStorage(uint256[] memory ids) internal {}

    //============================================ Implement Base Functions ===========================================
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public override {
        revert("User Deposits not allowed");
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        revert("User Withdraws not allowed");
    }

    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        return 0;
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // Makes a call to registry to get tokenId array from adaptor storage.
        Registry registry = Cellar(msg.sender).registry();
        bytes memory storageData = registry.getAdaptorStorage(
            msg.sender,
            keccak256(abi.encode(address(this), adaptorData))
        );

        uint256[] memory ids = abi.decode(storageData, (uint256[]));

        // Get exchnage rate between token0 and token1
        (ERC20 token0, ERC20 token1) = abi.decode(adaptorData, (ERC20, ERC20));
        uint256 price = PriceRouter(registry.getAddress(2)).getExchangeRate(token1, token0);

        uint160 sqrtPriceX96 = uint160(getSqrtPriceX96(10**token0.decimals(), price));

        int24 tick = getTick(sqrtPriceX96);

        uint256 amount0;
        uint256 amount1;

        for (uint256 i = 0; i < ids.length; i++) {
            (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = positionManager().positions(
                ids[i]
            );
            (uint256 amountA, uint256 amountB) = getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(tick),
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
            amount0 += amountA;
            amount1 += amountB;
        }

        return amount0 + amount1.mulDivDown(price, 10**token1.decimals());

        // Does a ton of math to determine the underlying value of all LP tokens it owns
        // This could also get away with making 1 call to the price router to get the exchange rate between the two tokens?
    }

    // Grabs token0 in adaptor data.
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    //============================================ High Level Callable Functions ============================================
    // Positions are arbitrary UniV3 positions that could be range orders, limit orders, or normal LP positions.
    function openPosition(uint256 amount0, uint256 amount1) public {
        // Creates a new NFT position and stores the NFT in the token Id array in adaptor storage
    }

    function closePosition(uint256 positionId) public {
        // Grabs array of token Ids from registry, finds corresponding token Id, then removes it from array, and closes position.
    }

    function addToPosition(
        uint256 amount0,
        uint256 amount1,
        uint256 positionId
    ) public {}

    function takeFromPosition(
        uint256 amount0,
        uint256 amount1,
        uint256 positionId
    ) public {}

    //Collects fees from all positions or maybe can specify from which ones?
    function collectFees() public {}

    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }

    function getSqrtPriceX96(uint256 priceA, uint256 priceB) public pure returns (uint256) {
        uint256 ratioX192 = (priceA << 192) / (priceB);
        return _sqrt(ratioX192);
    }

    function getTick(uint160 sqrtPriceX96) public pure returns (int24 tick) {
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    // Taken from LiquidityAmounts Lib
    /// @notice Computes the amount of token0 for a given amount of liquidity and a price range
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount0 The amount of token0
    function getAmount0ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            FullMath.mulDivDown(
                uint256(liquidity) << FixedPoint96.RESOLUTION,
                sqrtRatioBX96 - sqrtRatioAX96,
                sqrtRatioBX96
            ) / sqrtRatioAX96;
    }

    /// @notice Computes the amount of token1 for a given amount of liquidity and a price range
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount1 The amount of token1
    function getAmount1ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return FullMath.mulDivDown(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    /// @notice Computes the token0 and token1 value for a given amount of liquidity, the current
    /// pool prices and the prices at the tick boundaries
    /// @param sqrtRatioX96 A sqrt price representing the current pool prices
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }
}
