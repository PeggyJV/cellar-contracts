// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Cellar, Registry, PriceRouter } from "src/base/Cellar.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { console } from "@forge-std/Test.sol";
import { INonfungiblePositionManager } from "src/interfaces/external/INonfungiblePositionManager.sol";
// import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { TickMath } from "src/interfaces/external/TickMath.sol";
import { Math } from "src/utils/Math.sol";
import { FixedPoint96 } from "@uniswapV3C/libraries/FixedPoint96.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { console } from "@forge-std/Test.sol";

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
    using Math for uint256;
    using Address for address;

    /*
        adaptorData = abi.encode(token0, token1)
        adaptorStroage(written in registry) = abi.encode(uint256[] tokenIds)
    */

    //============================================ Global Functions ===========================================

    function positionManager() internal pure returns (INonfungiblePositionManager) {
        return INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    }

    //============================================ Implement Base Functions ===========================================
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert("User Deposits not allowed");
    }

    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
        revert("User Withdraws not allowed");
    }

    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // Get exchnage rate between token0 and token1

        (ERC20 token0, ERC20 token1) = abi.decode(adaptorData, (ERC20, ERC20));
        // uint256 price0 = PriceRouter(Cellar(msg.sender).registry().getAddress(2)).getValueInUSD(token0);
        // uint256 price1 = PriceRouter(Cellar(msg.sender).registry().getAddress(2)).getValueInUSD(token1);
        uint256 price = PriceRouter(Cellar(msg.sender).registry().getAddress(2)).getExchangeRate(token1, token0);
        console.log("Price", price);
        console.log("other", 10**token0.decimals());

        uint160 sqrtPriceX96 = uint160(getSqrtPriceX96(10**token0.decimals(), price));

        int24 tick = getTick(sqrtPriceX96);

        // Grab cellars balance of UniV3 NFTs.
        uint256 bal = positionManager().balanceOf(msg.sender);

        if (bal == 0) return 0;

        // Grab cellars array of token ids with multicall.
        bytes[] memory positionDataRequest = new bytes[](bal);
        for (uint256 i = 0; i < bal; i++) {
            positionDataRequest[i] = abi.encodeWithSignature("tokenOfOwnerByIndex(address,uint256)", msg.sender, i);
        }
        positionDataRequest = abi.decode(
            address(positionManager()).functionStaticCall(
                abi.encodeWithSignature("multicall(bytes[])", (positionDataRequest))
            ),
            (bytes[])
        );

        // Grab array of positions using previous token id array
        for (uint256 i = 0; i < bal; i++) {
            positionDataRequest[i] = abi.encodeWithSignature(
                "positions(uint256)",
                (abi.decode(positionDataRequest[i], (uint256)))
            );
        }
        positionDataRequest = abi.decode(
            address(positionManager()).functionStaticCall(
                abi.encodeWithSignature("multicall(bytes[])", (positionDataRequest))
            ),
            (bytes[])
        );

        // Loop through position data and sum total amount of Token 0 and Token 1 from LP positions that match token0 and token1.
        uint256 amount0;
        uint256 amount1;
        for (uint256 i = 0; i < bal; i++) {
            (, , address t0, address t1, , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = abi.decode(
                positionDataRequest[i],
                (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
            );

            // Skip LP tokens that are not for this position.
            if (t0 != address(token0) || t1 != address(token1)) continue;

            (uint256 amountA, uint256 amountB) = getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(tick),
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
            amount0 += amountA;
            amount1 += amountB;
        }
        console.log("DAI", amount0);
        console.log("USDC", amount1);

        // Amounts are in 12 decimals, convert them back to underlying.
        return amount0.changeDecimals(12, token0.decimals()) + amount1.mulDivDown(price, 1e12);
    }

    // Grabs token0 in adaptor data.
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    //============================================ High Level Callable Functions ============================================
    // Positions are arbitrary UniV3 positions that could be range orders, limit orders, or normal LP positions.
    function openPosition(
        ERC20 token0,
        ERC20 token1,
        uint256 amount0,
        uint256 amount1
    ) public {
        // Creates a new NFT position and stores the NFT in the token Id array in adaptor storage
        token0.safeApprove(address(positionManager()), amount0);
        token1.safeApprove(address(positionManager()), amount1);

        uint24 poolFee = 100;
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: poolFee,
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });
        uint256 tokenId;
        uint128 liquidity;
        (tokenId, liquidity, amount0, amount1) = positionManager().mint(params);
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

    //============================================ Internal Functions ============================================

    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }

    function getSqrtPriceX96(uint256 priceA, uint256 priceB) internal pure returns (uint256) {
        uint256 ratioX192 = (priceA << 192) / (priceB);
        return _sqrt(ratioX192);
    }

    function getTick(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
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
            mulDiv(uint256(liquidity) << FixedPoint96.RESOLUTION, sqrtRatioBX96 - sqrtRatioAX96, sqrtRatioBX96) /
            sqrtRatioAX96;
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

        return uint256(liquidity).mulDivDown(sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
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

    /// @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    /// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remainder Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2**256 + prod0
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0
        require(denominator > prod1);

        ///////////////////////////////////////////////
        // 512 by 256 division.
        ///////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0]
        // Compute remainder using mulmod
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // Subtract 256 bit number from 512 bit number
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator
        // Compute largest power of two divisor of denominator.
        // Always >= 1.
        uint256 tmp = 1 << 255;

        uint256 twos = (tmp | denominator) & denominator;
        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // Divide [prod1 prod0] by the factors of two
        assembly {
            prod0 := div(prod0, twos)
        }
        // Shift in bits from prod1 into prod0. For this we need
        // to flip `twos` such that it is 2**256 / twos.
        // If twos is zero, then it becomes one
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // Invert denominator mod 2**256
        // Now that denominator is an odd number, it has an inverse
        // modulo 2**256 such that denominator * inv = 1 mod 2**256.
        // Compute the inverse by starting with a seed that is correct
        // correct for four bits. That is, denominator * inv = 1 mod 2**4
        uint256 inv = (3 * denominator) ^ 2;
        // Now use Newton-Raphson iteration to improve the precision.
        // Thanks to Hensel's lifting lemma, this also works in modular
        // arithmetic, doubling the correct bits in each step.
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        // Because the division is now exact we can divide by multiplying
        // with the modular inverse of denominator. This will give us the
        // correct result modulo 2**256. Since the precoditions guarantee
        // that the outcome is less than 2**256, this is the final result.
        // We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inv;
        return result;
    }
}
