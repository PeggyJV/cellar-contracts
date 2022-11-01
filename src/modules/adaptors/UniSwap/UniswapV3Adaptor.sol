// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswapV3P/libraries/LiquidityAmounts.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Uniswap V3 Adaptor
 * @notice Allows Cellars to hold and interact with Uniswap V3 LP Positions.
 * @dev `balanceOf` credited to https://github.com/0xparashar/UniV3NFTOracle/blob/master/contracts/UniV3NFTOracle.sol
 * @author crispymangoes
 */
contract UniswapV3Adaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using SafeCast for uint256;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ERC20 token0, ERC20 token1)
    // Where:
    // `token0` is the token0 of the UniV3 LP pair this adaptor is working with
    // `token1` is the token1 of the UniV3 LP pair this adaptor is working with
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // Each UniV3 LP position is defined by `token0`, and `token1`,
    // so Cellars can theoretically have as many UniV3 LP positions with
    // the same underlying as they want(With any ticks, or any fees),
    // but doing so will increase the adaptors `balanceOf` gas cost
    // and is discouraged.
    //====================================================================

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Uniswap V3 Adaptor V 0.0"));
    }

    /**
     * @notice The Uniswap V3 NonfungiblePositionManager contract on Ethereum Mainnet.
     */
    function positionManager() internal pure returns (INonfungiblePositionManager) {
        return INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice User withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Calculates this positions LP tokens underlying worth in terms of `token0`.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // Get exchnage rate between token0 and token1.
        (ERC20 token0, ERC20 token1) = abi.decode(adaptorData, (ERC20, ERC20));
        uint256 price = PriceRouter(Cellar(msg.sender).registry().getAddress(PRICE_ROUTER_REGISTRY_SLOT()))
            .getExchangeRate(token1, token0);

        // Calculate current sqrtPrice.
        uint256 ratioX192 = ((10**token1.decimals()) << 192) / (price);
        uint160 sqrtPriceX96 = _sqrt(ratioX192).toUint160();

        // Grab cellars balance of UniV3 NFTs.
        uint256 bal = positionManager().balanceOf(msg.sender);

        // If cellar does not own any UniV3 positions it has no assets in UniV3.
        if (bal == 0) return 0;

        // Grab cellars array of token ids with `tokenOfOwnerByIndex` using multicall.
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

        // Grab array of positions using previous token id array.
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

        // Loop through position data and sum total amount of Token 0 and Token 1 from LP positions that match `token0` and `token1`.
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
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
            amount0 += amountA;
            amount1 += amountB;
        }

        // Return amount of `token0` + amount of `token1` converted into `token0`;
        return amount0 + amount1.mulDivDown(price, 10**token1.decimals());
    }

    /**
     * @notice Returns `token0`
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategist to open up arbritray Uniswap V3 positions.
     * @notice LP positions can be range orders or normal LP positions.
     * @notice If strategist specifies token0 and token1 for a position not properly set up, totalAssets check will revert.
     *         See Cellar.sol
     * @notice `tickLower`, and `tickUpper` MUST be valid ticks for the given `poolFee`
     *         `tickLower` % pool.tickSpacing() == 0
     *         `tickUpper` % pool.tickSpacing() == 0
     * @param token0 the token0 in the UniV3 pair
     * @param token1 the token1 in the UniV3 pair
     * @param poolFee specify which fee pool to open a position in
     * @param amount0 amount of `token0` to add to liquidity
     * @param amount1 amount of `token1` to add to liquidity
     * @param min0 the minimum amount of `token0` to add to liquidity
     * @param min1 the minimum amount of `token1` to add to liquidity
     * @param tickLower the lower liquidity tick
     * @param tickUpper the upper liquidity tick
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
        // Approve NonfungiblePositionManager to spend `token0` and `token1`.
        token0.safeApprove(address(positionManager()), amount0);
        token1.safeApprove(address(positionManager()), amount1);

        // Create mint params.
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

        // Supply liquidity to pool.
        (, , uint256 amount0Act, uint256 amount1Act) = positionManager().mint(params);

        // Zero out approvals if necessary.
        if (amount0Act < amount0) token0.safeApprove(address(positionManager()), 0);
        if (amount1Act < amount1) token1.safeApprove(address(positionManager()), 0);
    }

    /**
     * @notice Strategist attempted to interact with a Uniswap V3 position the cellar does not own.
     * @param positionId the id of the position the cellar does not own
     */
    error UniswapV3Adaptor__NotTheOwner(uint256 positionId);

    /**
     * @notice Allows strategist to close Uniswap V3 positions.
     * @dev transfers NFT to DEAD address to save on gas while looping in `balanceOf`.
     * @param positionId the UniV3 LP NFT id to close
     * @param min0 the minimum amount of `token0` to get from closing this position
     * @param min1 the minimum amount of `token1` to get from closing this position
     */
    function closePosition(
        uint256 positionId,
        uint256 min0,
        uint256 min1
    ) public {
        // Make sure the cellar owns this positionId. Also checks the positionId exists.
        if (positionManager().ownerOf(positionId) != address(this)) revert UniswapV3Adaptor__NotTheOwner(positionId);

        // Create decrease liquidity params.
        (, , , , , , , uint128 liquidity, , , , ) = positionManager().positions(positionId);
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: positionId,
                liquidity: liquidity,
                amount0Min: min0,
                amount1Min: min1,
                deadline: block.timestamp
            });

        // Decrease liquidity in pool.
        positionManager().decreaseLiquidity(params);

        // Collect principal and fees before "burning" NFT.
        collectFees(positionId, type(uint128).max, type(uint128).max);

        // Position now has no more liquidity, so transfer NFT to dead address to save on `balanceOf` gas usage.
        // Transfer token to a dead address.
        positionManager().transferFrom(address(this), address(1), positionId);
    }

    /**
     * @notice Allows strategist to add to existing Uniswap V3 positions.
     * @param positionId the UniV3 LP NFT id to add liquidity to
     * @param amount0 amount of `token0` to add to liquidity
     * @param amount1 amount of `token1` to add to liquidity
     * @param min0 the minimum amount of `token0` to add to liquidity
     * @param min1 the minimum amount of `token1` to add to liquidity
     */
    function addToPosition(
        uint256 positionId,
        uint256 amount0,
        uint256 amount1,
        uint256 min0,
        uint256 min1
    ) public {
        // Make sure the cellar owns this positionId. Also checks the positionId exists.
        if (positionManager().ownerOf(positionId) != address(this)) revert UniswapV3Adaptor__NotTheOwner(positionId);

        // Approve NonfungiblePositionManager to spend `token0` and `token1`.
        (, , address t0, address t1, , , , , , , , ) = positionManager().positions(positionId);
        ERC20(t0).safeApprove(address(positionManager()), amount0);
        ERC20(t1).safeApprove(address(positionManager()), amount1);

        // Create increase liquidity params.
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: positionId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: min0,
                amount1Min: min1,
                deadline: block.timestamp
            });

        // Increase liquidity in pool.
        positionManager().increaseLiquidity(params);
    }

    /**
     * @notice Strategist attempted to remove all of a positions liquidity using `takeFromPosition`,
     *         but they need to use `closePosition`.
     */
    error UniswapV3Adaptor__CallClosePosition();

    /**
     * @notice Allows strategist to take from existing Uniswap V3 positions.
     * @param positionId the UniV3 LP NFT id to take from
     * @param liquidity the amount of liquidity to take from the position
     * @param min0 the minimum amount of `token0` to get from taking liquidity
     * @param min1 the minimum amount of `token1` to get from taking liquidity
     */
    function takeFromPosition(
        uint256 positionId,
        uint128 liquidity,
        uint256 min0,
        uint256 min1
    ) public {
        // Make sure the cellar owns this positionId. Also checks the positionId exists.
        if (positionManager().ownerOf(positionId) != address(this)) revert UniswapV3Adaptor__NotTheOwner(positionId);

        // Check that the position isn't being closed fully.
        (, , , , , , , uint128 positionLiquidity, , , , ) = positionManager().positions(positionId);
        if (liquidity >= positionLiquidity) revert UniswapV3Adaptor__CallClosePosition();

        // Create decrease liquidity params.
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: positionId,
                liquidity: liquidity,
                amount0Min: min0,
                amount1Min: min1,
                deadline: block.timestamp
            });

        // Decrease liquidity in pool.
        (uint256 amount0, uint256 amount1) = positionManager().decreaseLiquidity(params);

        // Collect principal from position.
        collectFees(positionId, amount0.toUint128(), amount1.toUint128());
    }

    /**
     * @notice Allows strategist to collect fees from existing Uniswap V3 positions.
     * @param positionId the UniV3 LP NFT id to collect fees from
     * @param amount0 amount of `token0` fees to collect use type(uint128).max to get collect all
     * @param amount1 amount of `token1` fees to collect use type(uint128).max to get collect all
     */
    function collectFees(
        uint256 positionId,
        uint128 amount0,
        uint128 amount1
    ) public {
        // Make sure the cellar owns this positionId. Also checks the positionId exists.
        if (positionManager().ownerOf(positionId) != address(this)) revert UniswapV3Adaptor__NotTheOwner(positionId);

        // Create fee collection params.
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: positionId,
            recipient: address(this),
            amount0Max: amount0,
            amount1Max: amount1
        });

        // Collect fees.
        positionManager().collect(params);
    }

    //============================================ Helper Functions ============================================
    /**
     * @notice Calculates the square root of the input.
     */
    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }
}
