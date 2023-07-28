// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswapV3P/libraries/LiquidityAmounts.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

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

    // The Tracker value MUST be a hardcoded address. Do not allow strategists
    // to enter their own tracker, or else _purgePosition can be used to
    // gain an unused approval.
    //====================================================================

    /**
     * @notice Strategist attempted to interact with a Uniswap V3 position the cellar does not own.
     * @param tokenId the id of the position the cellar does not own
     */
    error UniswapV3Adaptor__NotTheOwner(uint256 tokenId);

    /**
     * @notice Strategist attempted to move liquidity into untracked LP positions.
     * @param token0 The token0 of the untracked position
     * @param token1 The token1 of the untracked position
     */
    error UniswapV3Adaptor__UntrackedLiquidity(address token0, address token1);

    /**
     * @notice Strategist attempted an action with a position id that was not in the tracker.
     * @param tokenId The Uniswap V3 Position Id
     */
    error UniswapV3Adaptor__TokenIdNotFoundInTracker(uint256 tokenId);

    /**
     * @notice Strategsit attempted to purge a position with liquidity.
     */
    error UniswapV3Adaptor__PurgingPositionWithLiquidity(uint256 tokenId);

    /**
     * @notice The Uniswap V3 Position Manager contract on current network.
     * @notice For mainnet use 0xC36442b4a4522E871399CD717aBDD847Ab11FE88.
     */
    INonfungiblePositionManager public immutable positionManager;

    /**
     * @notice The Uniswap V3 Position Tracker on current network.
     * @notice For mainnet use 0xf2854d84D9Dd27eCcD6aB20b3F66111a51bb56d2.
     */
    UniswapV3PositionTracker public immutable tracker;

    constructor(address _positionManager, address _tracker) {
        positionManager = INonfungiblePositionManager(_positionManager);
        tracker = UniswapV3PositionTracker(_tracker);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Uniswap V3 Adaptor V 1.4"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
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
        // Get exchange rate between token0 and token1.
        (ERC20 token0, ERC20 token1) = abi.decode(adaptorData, (ERC20, ERC20));

        // Grab cellars Uniswap V3 positions from tracker.
        uint256[] memory positions = tracker.getTokens(msg.sender, token0, token1);

        // If cellar does not own any UniV3 positions it has no assets in UniV3.
        if (positions.length == 0) return 0;

        uint256 precisionPrice;
        {
            PriceRouter priceRouter = Cellar(msg.sender).priceRouter();
            uint256 baseToUSD = priceRouter.getPriceInUSD(token1);
            uint256 quoteToUSD = priceRouter.getPriceInUSD(token0);
            baseToUSD = baseToUSD * 1e18; // Multiply by 1e18 to keep some precision.
            precisionPrice = baseToUSD.mulDivDown(10 ** token0.decimals(), quoteToUSD);
        }

        // Calculate current sqrtPrice.
        uint256 ratioX192 = ((10 ** token1.decimals()) << 192) / (precisionPrice / 1e18);
        uint160 sqrtPriceX96 = _sqrt(ratioX192).toUint160();

        bytes[] memory positionDataRequest = new bytes[](positions.length);

        // Grab array of positions using previous token id array.
        // `positionDataRequest` currently holds abi encoded token ids that caller owns.
        for (uint256 i = 0; i < positions.length; i++) {
            positionDataRequest[i] = abi.encodeWithSignature("positions(uint256)", positions[i]);
        }
        positionDataRequest = abi.decode(
            address(positionManager).functionStaticCall(
                abi.encodeWithSignature("multicall(bytes[])", (positionDataRequest))
            ),
            (bytes[])
        );

        // Loop through position data and sum total amount of Token 0 and Token 1 from LP positions that match `token0` and `token1`.
        uint256 amount0;
        uint256 amount1;
        for (uint256 i = 0; i < positions.length; i++) {
            if (positionManager.ownerOf(positions[i]) != msg.sender) continue;
            (, , address t0, address t1, , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = abi.decode(
                positionDataRequest[i],
                (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
            );

            // Skip LP tokens that are not for this position, or if there is no liquidity in the position.
            if (t0 != address(token0) || t1 != address(token1) || liquidity == 0) continue;

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
        amount1 = amount1.mulDivDown(precisionPrice, 10 ** token1.decimals());
        amount1 = amount1 / 1e18; // Remove precision scaler.
        return amount0 + amount1;
    }

    /**
     * @notice Returns `token0`
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    /**
     * @notice When positions are added to the Registry, this function can be used in order to figure out
     *         what assets this adaptor needs to price, and confirm pricing is properly setup.
     */
    function assetsUsed(bytes memory adaptorData) public pure override returns (ERC20[] memory assets) {
        assets = new ERC20[](2);
        (ERC20 token0, ERC20 token1) = abi.decode(adaptorData, (ERC20, ERC20));
        assets[0] = token0;
        assets[1] = token1;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
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
        // Check that Uniswap V3 position is properly set up to be tracked in the Cellar.
        _checkUniswapV3PositionIsUsed(token0, token1);

        amount0 = _maxAvailable(token0, amount0);
        amount1 = _maxAvailable(token1, amount1);
        // Approve NonfungiblePositionManager to spend `token0` and `token1`.
        token0.safeApprove(address(positionManager), amount0);
        token1.safeApprove(address(positionManager), amount1);

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
        (uint256 tokenId, , , ) = positionManager.mint(params);

        // Add new token to the array.
        tracker.addPositionToArray(tokenId, token0, token1);

        // Zero out approvals if necessary.
        _revokeExternalApproval(token0, address(positionManager));
        _revokeExternalApproval(token1, address(positionManager));
    }

    /**
     * @notice Allows strategist to close Uniswap V3 positions.
     * @dev transfers NFT to DEAD address to save on gas while looping in `balanceOf`.
     * @param tokenId the UniV3 LP NFT id to close
     * @param min0 the minimum amount of `token0` to get from closing this position
     * @param min1 the minimum amount of `token1` to get from closing this position
     */
    function closePosition(uint256 tokenId, uint256 min0, uint256 min1) public {
        // Pass in true for `collectFees` since the token will be sent to the dead address.
        // `_takeFromPosition checks if tokenId is owned.`
        (, , address t0, address t1, , , , uint128 currentLiquidity, , , , ) = positionManager.positions(tokenId);

        _takeFromPosition(tokenId, currentLiquidity, min0, min1, true);

        // Position now has no more liquidity, or fees, so purge it.
        _purgePosition(tokenId, ERC20(t0), ERC20(t1));
    }

    /**
     * @notice Allows strategist to add to existing Uniswap V3 positions.
     * @param tokenId the UniV3 LP NFT id to add liquidity to
     * @param amount0 amount of `token0` to add to liquidity
     * @param amount1 amount of `token1` to add to liquidity
     * @param min0 the minimum amount of `token0` to add to liquidity
     * @param min1 the minimum amount of `token1` to add to liquidity
     */
    function addToPosition(uint256 tokenId, uint256 amount0, uint256 amount1, uint256 min0, uint256 min1) public {
        _checkTokenId(tokenId);

        // Read `token0` and `token1` from position manager.
        (, , address t0, address t1, , , , , , , , ) = positionManager.positions(tokenId);
        ERC20 token0 = ERC20(t0);
        ERC20 token1 = ERC20(t1);

        // Make sure position is in tracker, otherwise outside user sent it to the cellar so revert.
        if (!tracker.checkIfPositionIsInTracker(address(this), tokenId, token0, token1))
            revert UniswapV3Adaptor__TokenIdNotFoundInTracker(tokenId);

        // Check that Uniswap V3 position is properly set up to be tracked in the Cellar.
        _checkUniswapV3PositionIsUsed(token0, token1);

        amount0 = _maxAvailable(token0, amount0);
        amount1 = _maxAvailable(token1, amount1);

        // Approve NonfungiblePositionManager to spend `token0` and `token1`.
        token0.safeApprove(address(positionManager), amount0);
        token1.safeApprove(address(positionManager), amount1);

        // Create increase liquidity params.
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: min0,
                amount1Min: min1,
                deadline: block.timestamp
            });

        // Increase liquidity in pool.
        positionManager.increaseLiquidity(params);

        // Zero out approvals if necessary.
        _revokeExternalApproval(token0, address(positionManager));
        _revokeExternalApproval(token1, address(positionManager));
    }

    /**
     * @notice Allows strategist to take from existing Uniswap V3 positions.
     * @dev This leaves the tokenId in the tracker so it can be used at a later date.
     * @param tokenId the UniV3 LP NFT id to take from
     * @param liquidity the amount of liquidity to take from the position
     * @param min0 the minimum amount of `token0` to get from taking liquidity
     * @param min1 the minimum amount of `token1` to get from taking liquidity
     * @param takeFees bool indicating whether to collect principal(if false),
     *                    or principal + fees (if true)
     */
    function takeFromPosition(uint256 tokenId, uint128 liquidity, uint256 min0, uint256 min1, bool takeFees) public {
        (, , , , , , , uint128 currentLiquidity, , , , ) = positionManager.positions(tokenId);

        // If uint128 max is specified for liquidity, withdraw the full amount.
        if (liquidity == type(uint128).max) liquidity = currentLiquidity;

        _takeFromPosition(tokenId, liquidity, min0, min1, takeFees);
    }

    /**
     * @notice Allows strategist to collect fees from existing Uniswap V3 positions.
     * @param tokenId the UniV3 LP NFT id to collect fees from
     * @param amount0 amount of `token0` fees to collect use type(uint128).max to get collect all
     * @param amount1 amount of `token1` fees to collect use type(uint128).max to get collect all
     */
    function collectFees(uint256 tokenId, uint128 amount0, uint128 amount1) external {
        _checkTokenId(tokenId);

        _collectFees(tokenId, amount0, amount1);
    }

    /**
     * @notice Allows strategist to purge a single zero liquidity LP position from tracker.
     * @dev If position has liquidity, then revert.
     * @dev Collect fees from position before purging.
     */
    function purgeSinglePosition(uint256 tokenId) public {
        (, , address t0, address t1, , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);
        if (liquidity == 0) {
            _collectFees(tokenId, type(uint128).max, type(uint128).max);
            _purgePosition(tokenId, ERC20(t0), ERC20(t1));
        } else revert UniswapV3Adaptor__PurgingPositionWithLiquidity(tokenId);
    }

    /**
     * @notice Allows strategist to purge zero liquidity LP positions from tracker.
     * @dev Loops through tracker array and if a position has no liquidity, then
     *      Fees are collected, and position is purged.
     */
    function purgeAllZeroLiquidityPositions(ERC20 token0, ERC20 token1) public {
        uint256[] memory positions = tracker.getTokens(address(this), token0, token1);

        for (uint256 i; i < positions.length; ++i) {
            (, , address t0, address t1, , , , uint128 liquidity, , , , ) = positionManager.positions(positions[i]);

            if (liquidity == 0) {
                _collectFees(positions[i], type(uint128).max, type(uint128).max);
                _purgePosition(positions[i], ERC20(t0), ERC20(t1));
            }
        }
    }

    /**
     * @notice Allows strategist to remove tracked positions that are not owned by the cellar.
     *         In order for this situation to happen then an exploit needs to be found where UniV3
     *         NFTs can be transferred out of the cellar during rebalance calls, so it is unlikely.
     * @dev Reverts if tokenId is owned by cellar, or if tokenId is not in tracked array.
     */
    function removeUnOwnedPositionFromTracker(uint256 tokenId, ERC20 token0, ERC20 token1) public {
        tracker.removePositionFromArrayThatIsNotOwnedByCaller(tokenId, token0, token1);
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

    /**
     * @notice Checks that given `tokenId` exists, and is owned by the cellar.
     */
    function _checkTokenId(uint256 tokenId) internal view {
        // Make sure the cellar owns this tokenId. Also checks the tokenId exists.
        if (positionManager.ownerOf(tokenId) != address(this)) revert UniswapV3Adaptor__NotTheOwner(tokenId);
    }

    /**
     * @notice Check if token0 and token1 correspond to a UniswapV3 Cellar position.
     */
    function _checkUniswapV3PositionIsUsed(ERC20 token0, ERC20 token1) internal view {
        // Check that Uniswap V3 position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(token0, token1)));
        uint32 registryPositionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(registryPositionId))
            revert UniswapV3Adaptor__UntrackedLiquidity(address(token0), address(token1));
    }

    /**
     * @notice Helper function to collect Uniswap V3 position fees.
     */
    function _collectFees(uint256 tokenId, uint128 amount0, uint128 amount1) internal {
        // Create fee collection params.
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: amount0,
            amount1Max: amount1
        });

        // Collect fees.
        positionManager.collect(params);
    }

    /**
     * @notice Helper function to get rid of unused position.
     * @dev The Tracker value MUST be a hardcoded address. Do not allow strategists
     * to enter their own tracker, or else _purgePosition can be used to
     * gain an unused approval.
     */
    function _purgePosition(uint256 tokenId, ERC20 token0, ERC20 token1) internal {
        positionManager.approve(address(tracker), tokenId);
        tracker.removePositionFromArray(tokenId, token0, token1);
    }

    /**
     * @notice Helper function to take liquidity from UniV3 LP positions.
     */
    function _takeFromPosition(uint256 tokenId, uint128 liquidity, uint256 min0, uint256 min1, bool takeFees) internal {
        _checkTokenId(tokenId);

        // Create decrease liquidity params.
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: min0,
                amount1Min: min1,
                deadline: block.timestamp
            });

        // Decrease liquidity in pool.
        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(params);

        if (takeFees) {
            // Collect principal + fees from position.
            _collectFees(tokenId, type(uint128).max, type(uint128).max);
        } else {
            // Collect principal from position.
            _collectFees(tokenId, amount0.toUint128(), amount1.toUint128());
        }
    }
}
