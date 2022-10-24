// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Cellar, Registry, PriceRouter } from "src/base/Cellar.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { PositionValue } from "@uniswapV3P/libraries/PositionValue.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswapV3P/libraries/LiquidityAmounts.sol";
import { Math } from "src/utils/Math.sol";
import { FixedPoint96 } from "@uniswapV3C/libraries/FixedPoint96.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { console } from "@forge-std/Test.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/**
 * @title Uniswap V3 Adaptor
 * @notice Cellars make delegate call to this contract in order to interact with other Cellar contracts.
 * @author crispymangoes
 */

//balanceOf inspired by https://github.com/0xparashar/UniV3NFTOracle/blob/master/contracts/UniV3NFTOracle.sol
contract UniswapV3Adaptor is BaseAdaptor, ERC721Holder {
    using SafeERC20 for ERC20;
    using Math for uint256;
    using Address for address;

    /*
        adaptorData = abi.encode(token0, token1)
    */

    //============================================ Global Functions ===========================================

    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Uniswap V3 Adaptor V 0.0"));
    }

    function positionManager() internal pure returns (INonfungiblePositionManager) {
        return INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    }

    //============================================ Implement Base Functions ===========================================
    error UniswapV3Adaptor__UserDepositAndWithdrawNotAllowed();

    /**
     * @notice User deposits are not allowed.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert UniswapV3Adaptor__UserDepositAndWithdrawNotAllowed();
    }

    /**
     * @notice User withdraws are not allowed.
     */
    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
        revert UniswapV3Adaptor__UserDepositAndWithdrawNotAllowed();
    }

    /**
     * @notice User withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * Gets all token Id caller owns, then sums up amounts for UniV3 positions that match `adaptorData` arguments.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // Get exchnage rate between token0 and token1
        (ERC20 token0, ERC20 token1) = abi.decode(adaptorData, (ERC20, ERC20));
        uint256 price = PriceRouter(Cellar(msg.sender).registry().getAddress(2)).getExchangeRate(token1, token0);

        uint256 ratioX192 = ((10**token1.decimals()) << 192) / (price);
        uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(ratioX192));

        // Grab cellars balance of UniV3 NFTs.
        uint256 bal = positionManager().balanceOf(msg.sender);

        // If cellar does not own any UniV3 positions it has no assets in UniV3.
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
        // `positionDataRequest` currently holds abi encoded token ids that caller owns.
        for (uint256 i = 0; i < bal; i++) {
            positionDataRequest[i] = abi.encodeWithSignature(
                "positions(uint256)",
                abi.decode(positionDataRequest[i], (uint256))
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

            (uint256 amountA, uint256 amountB) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96, // TickMath.getSqrtRatioAtTick(tick),
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
            amount0 += amountA;
            amount1 += amountB;
        }

        return amount0 + amount1.mulDivDown(price, 10**token1.decimals());
    }

    // Grabs token0 in adaptor data.
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    //============================================ High Level Callable Functions ============================================
    // Positions are arbitrary UniV3 positions that could be range orders, limit orders, or normal LP positions.
    /**
     * @notice Allows strategist to open up arbritray Uniswap V3 positions.
     * @notice If strategist specifies token0 and token1 for a position not properly set up this call will revert.
     */
    function openPosition(
        ERC20 token0,
        ERC20 token1,
        uint24 poolFee,
        uint256 amount0,
        uint256 amount1,
        uint256 min0,
        uint256 min1,
        int24 tickLower,
        int24 tickUpper
    ) public {
        // Creates a new NFT position and stores the NFT in the token Id array in adaptor storage
        token0.safeApprove(address(positionManager()), amount0);
        token1.safeApprove(address(positionManager()), amount1);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: min0,
            amount1Min: min1,
            recipient: address(this),
            deadline: block.timestamp
        });
        (, , uint256 amount0Act, uint256 amount1Act) = positionManager().mint(params);
        // Zero out approvals.
        if (amount0Act < amount0) token0.safeApprove(address(positionManager()), 0);
        if (amount1Act < amount1) token1.safeApprove(address(positionManager()), 0);
    }

    function closePosition(
        uint256 positionId,
        uint256 min0,
        uint256 min1
    ) public {
        require(address(this) == positionManager().ownerOf(positionId), "Cellar does not own this token.");
        (, , , , , , , uint128 liquidity, , , , ) = positionManager().positions(positionId);
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: positionId,
                liquidity: liquidity,
                amount0Min: min0,
                amount1Min: min1,
                deadline: block.timestamp
            });
        positionManager().decreaseLiquidity(params);

        // Collect principal and fees before "burning" NFT.
        collectFees(positionId, type(uint128).max, type(uint128).max);

        // Position now has no more liquidity, so transfer NFT to dead address to save on `balanceOf` gas usage.
        // Transfer token to a dead address.
        positionManager().transferFrom(address(this), address(1), positionId);
    }

    function addToPosition(
        uint256 positionId,
        uint256 amount0,
        uint256 amount1,
        uint256 min0,
        uint256 min1
    ) public {
        require(address(this) == positionManager().ownerOf(positionId), "Cellar does not own this token.");
        (, , address t0, address t1, , , , , , , , ) = positionManager().positions(positionId);
        ERC20(t0).safeApprove(address(positionManager()), amount0);
        ERC20(t1).safeApprove(address(positionManager()), amount1);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: positionId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: min0,
                amount1Min: min1,
                deadline: block.timestamp
            });

        positionManager().increaseLiquidity(params);
    }

    function takeFromPosition(
        uint256 positionId,
        uint128 liquidity,
        uint256 min0,
        uint256 min1
    ) public {
        require(address(this) == positionManager().ownerOf(positionId), "Cellar does not own this token.");
        (, , , , , , , uint128 positionLiquidity, , , , ) = positionManager().positions(positionId);
        require(positionLiquidity > liquidity, "Call closePosition.");
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: positionId,
                liquidity: liquidity,
                amount0Min: min0,
                amount1Min: min1,
                deadline: block.timestamp
            });
        (uint256 amount0, uint256 amount1) = positionManager().decreaseLiquidity(params);
        collectFees(positionId, uint128(amount0), uint128(amount1)); //TODO use safeCast
        //TODO So maybe the way to get the principle out of the position, and no fees is to call collect fees, but instead of doing the max, use the amounts you get from decrease liquidity.
    }

    //Collects fees from all positions or maybe can specify from which ones?
    function collectFees(
        uint256 tokenId,
        uint128 amount0,
        uint128 amount1
    ) public {
        require(address(this) == positionManager().ownerOf(tokenId), "Cellar does not own this token.");
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: amount0,
            amount1Max: amount1
        });

        positionManager().collect(params);
    }

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
}
