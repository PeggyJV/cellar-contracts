// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswapV3P/libraries/LiquidityAmounts.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SinglePositionUniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/SinglePositionUniswapV3PositionTracker.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";

// TODO remove
import { console } from "@forge-std/Test.sol";

/**
 * @title Uniswap V3 Adaptor
 * @notice Allows Cellars to hold and interact with Uniswap V3 LP Positions.
 * @dev `balanceOf` credited to https://github.com/0xparashar/UniV3NFTOracle/blob/master/contracts/UniV3NFTOracle.sol
 * @author crispymangoes
 */
contract SinglePositionUniswapV3Adaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using SafeCast for uint256;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address pool, uint256 index)
    // Where:
    // `token0` is the token0 of the UniV3 LP pair this adaptor is working with
    // `token1` is the token1 of the UniV3 LP pair this adaptor is working with
    //================= Configuration Data Specification =================
    // configurationData = abi.encode(bool isLiquid)
    // Where:
    // `isLiquid` dictates whether the position is liquid or not
    // If true:
    //      position can support use withdraws
    // else:
    //      position can not support user withdraws
    //
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
     */
    error UniswapV3Adaptor__UntrackedLiquidity(address pool, uint256 index);

    /**
     * @notice Strategist attempted an action with a position id that was not in the tracker.
     * @param index The tracker index with no position
     */
    error UniswapV3Adaptor__PositionNotInTracker(uint256 index);

    /**
     * @notice Strategsit attempted to purge a position with liquidity.
     */
    error UniswapV3Adaptor__PurgingPositionWithLiquidity(uint256 tokenId);

    // TODO natspec
    error UniswapV3Adaptor__TrackerIndexAlreadyUsed(uint256 index);
    error UniswapV3Adaptor__WrongTokenIdRemoved(uint256 requestedTokenIdToRemove, uint256 actualTokenIdRemoved);

    /**
     * @notice The Uniswap V3 Position Manager contract on current network.
     * @notice For mainnet use 0xC36442b4a4522E871399CD717aBDD847Ab11FE88.
     */
    INonfungiblePositionManager public immutable positionManager;

    /**
     * @notice The Uniswap V3 Position Tracker on current network.
     * @notice For mainnet use 0xf2854d84D9Dd27eCcD6aB20b3F66111a51bb56d2.
     */
    SinglePositionUniswapV3PositionTracker public immutable tracker;

    constructor(address _positionManager, address _tracker) {
        positionManager = INonfungiblePositionManager(_positionManager);
        tracker = SinglePositionUniswapV3PositionTracker(_tracker);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Single Position Uniswap V3 Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    // TODO natspec
    /**
     * @notice
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public override {
        bool isLiquid = abi.decode(configurationData, (bool));
        if (!isLiquid) revert BaseAdaptor__UserWithdrawsNotAllowed();

        _externalReceiverCheck(receiver);
        // Get the percent of liquidity to withdraw.
        (uint256 balance, uint128 liquidity, uint256 tokenId, ERC20 token0, ERC20 token1) = _positionData(
            address(this),
            adaptorData
        );
        uint256 percentToWithdraw = assets.mulDivDown(1e18, balance);
        uint128 liquidityToWithdraw = uint128((liquidity * percentToWithdraw) / 1e18);

        // Do not take fees so that Callers can not influence share price by taking fees.
        (uint256 amount0, uint256 amount1) = _takeFromPosition(tokenId, liquidityToWithdraw, 0, 0, false);

        // Transfer assets to receiver.
        if (amount0 > 0) token0.safeTransfer(receiver, amount0);
        if (amount1 > 0) token1.safeTransfer(receiver, amount1);
    }

    /**
     * @notice User withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256 withdrawable) {
        bool isLiquid = abi.decode(configurationData, (bool));
        if (isLiquid) (withdrawable, , , , ) = _positionData(msg.sender, adaptorData);
        // else withdrawable is 0.
    }

    /**
     * @notice Calculates this positions LP tokens underlying worth in terms of `token0`.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256 balance) {
        (balance, , , , ) = _positionData(msg.sender, adaptorData);
    }

    /**
     * @notice Returns `token0`
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IUniswapV3Pool pool = abi.decode(adaptorData, (IUniswapV3Pool));
        return ERC20(pool.token0());
    }

    /**
     * @notice When positions are added to the Registry, this function can be used in order to figure out
     *         what assets this adaptor needs to price, and confirm pricing is properly setup.
     */
    function assetsUsed(bytes memory adaptorData) public view override returns (ERC20[] memory assets) {
        assets = new ERC20[](2);
        IUniswapV3Pool pool = abi.decode(adaptorData, (IUniswapV3Pool));
        assets[0] = ERC20(pool.token0());
        assets[1] = ERC20(pool.token1());
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
     * @param pool the Uniswap V3 Pool to join
     * @param index the index to use in tracker
     * @param amount0 amount of `token0` to add to liquidity
     * @param amount1 amount of `token1` to add to liquidity
     * @param min0 the minimum amount of `token0` to add to liquidity
     * @param min1 the minimum amount of `token1` to add to liquidity
     * @param tickLower the lower liquidity tick
     * @param tickUpper the upper liquidity tick
     */
    function openPosition(
        IUniswapV3Pool pool,
        uint256 index,
        uint256 amount0,
        uint256 amount1,
        uint256 min0,
        uint256 min1,
        int24 tickLower,
        int24 tickUpper
    ) public {
        if (tracker.getCallerTokenAtIndex(address(pool), index) != 0)
            revert UniswapV3Adaptor__TrackerIndexAlreadyUsed(index);

        // Check that Uniswap V3 position is properly set up to be tracked in the Cellar.
        _checkUniswapV3PositionIsUsed(pool, index);

        ERC20 token0 = ERC20(pool.token0());
        ERC20 token1 = ERC20(pool.token1());

        amount0 = _maxAvailable(token0, amount0);
        amount1 = _maxAvailable(token1, amount1);
        // Approve NonfungiblePositionManager to spend `token0` and `token1`.
        token0.safeApprove(address(positionManager), amount0);
        token1.safeApprove(address(positionManager), amount1);

        // Create mint params.
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: pool.fee(),
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
        tracker.addPositionToTracker(tokenId, address(pool), index);

        // Zero out approvals if necessary.
        _revokeExternalApproval(token0, address(positionManager));
        _revokeExternalApproval(token1, address(positionManager));
    }

    /**
     * @notice Allows strategist to close Uniswap V3 positions.
     * @dev transfers NFT to DEAD address to save on gas while looping in `balanceOf`.
     * @param pool the Uniswap V3 Pool to join
     * @param index the index to use in tracker
     * @param min0 the minimum amount of `token0` to get from closing this position
     * @param min1 the minimum amount of `token1` to get from closing this position
     */
    function closePosition(IUniswapV3Pool pool, uint256 index, uint256 min0, uint256 min1) public {
        uint256 tokenId = tracker.getCallerTokenAtIndex(address(pool), index);
        if (tokenId == 0) revert UniswapV3Adaptor__PositionNotInTracker(index);

        // Pass in true for `collectFees` since the token will be sent to the dead address.
        // `_takeFromPosition checks if tokenId is owned.`
        (, , , , , , , uint128 currentLiquidity, , , , ) = positionManager.positions(tokenId);

        _takeFromPosition(tokenId, currentLiquidity, min0, min1, true);

        // Position now has no more liquidity, or fees, so purge it.
        _purgePosition(tokenId, address(pool), index);
    }

    /**
     * @notice Allows strategist to add to existing Uniswap V3 positions.
     * @param pool the Uniswap V3 Pool to join
     * @param index the index to use in tracker
     * @param amount0 amount of `token0` to add to liquidity
     * @param amount1 amount of `token1` to add to liquidity
     * @param min0 the minimum amount of `token0` to add to liquidity
     * @param min1 the minimum amount of `token1` to add to liquidity
     */
    function addToPosition(
        IUniswapV3Pool pool,
        uint256 index,
        uint256 amount0,
        uint256 amount1,
        uint256 min0,
        uint256 min1
    ) public {
        /// Note we do not check if the position is setup to be used with the Cellar
        // because we enfroce that tokenId is non zero, which can only happen
        // if openPosition is called first.
        uint256 tokenId = tracker.getCallerTokenAtIndex(address(pool), index);
        if (tokenId == 0) revert UniswapV3Adaptor__PositionNotInTracker(index);

        // Read `token0` and `token1` from position manager.
        (, , address t0, address t1, , , , , , , , ) = positionManager.positions(tokenId);
        ERC20 token0 = ERC20(t0);
        ERC20 token1 = ERC20(t1);

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
        /// Note intentionally do not check if position is owned by Cellar.
        // This function will only add value to the Cellar.

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
    function purgeSinglePosition(address pool, uint256 index) public {
        uint256 tokenId = tracker.getCallerTokenAtIndex(address(pool), index);

        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);
        if (liquidity == 0) {
            _collectFees(tokenId, type(uint128).max, type(uint128).max);
            _purgePosition(tokenId, pool, index);
        } else revert UniswapV3Adaptor__PurgingPositionWithLiquidity(tokenId);
    }

    /**
     * @notice Allows strategist to remove tracked positions that are not owned by the cellar.
     *         In order for this situation to happen then an exploit needs to be found where UniV3
     *         NFTs can be transferred out of the cellar during rebalance calls, so it is unlikely.
     * @dev Reverts if tokenId is owned by cellar, or if tokenId is not in tracked array.
     */
    function removeUnOwnedPositionFromTracker(address pool, uint256 index) public {
        tracker.removePositionThatIsNotOwnedByCaller(pool, index);
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
    function _checkUniswapV3PositionIsUsed(IUniswapV3Pool pool, uint256 index) internal view {
        // Check that Uniswap V3 position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(pool, index)));
        uint32 registryPositionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(registryPositionId))
            revert UniswapV3Adaptor__UntrackedLiquidity(address(pool), index);
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
    function _purgePosition(uint256 tokenId, address pool, uint256 index) internal {
        positionManager.approve(address(tracker), tokenId);
        uint256 tokenIdRemoved = tracker.removePositionFromTracker(pool, index);
        if (tokenIdRemoved != tokenId) revert UniswapV3Adaptor__WrongTokenIdRemoved(tokenId, tokenIdRemoved);
    }

    /**
     * @notice Helper function to take liquidity from UniV3 LP positions.
     */
    function _takeFromPosition(
        uint256 tokenId,
        uint128 liquidity,
        uint256 min0,
        uint256 min1,
        bool takeFees
    ) internal returns (uint256 amount0, uint256 amount1) {
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
        (amount0, amount1) = positionManager.decreaseLiquidity(params);

        if (takeFees) {
            // Collect principal + fees from position.
            _collectFees(tokenId, type(uint128).max, type(uint128).max);
        } else {
            // Collect principal from position.
            _collectFees(tokenId, amount0.toUint128(), amount1.toUint128());
        }
    }

    function _positionData(
        address caller,
        bytes memory adaptorData
    ) internal view returns (uint256, uint128, uint256 position, ERC20 token0, ERC20 token1) {
        // Get exchange rate between token0 and token1.
        uint160 sqrtPriceX96;
        {
            (IUniswapV3Pool pool, uint256 index) = abi.decode(adaptorData, (IUniswapV3Pool, uint256));

            token0 = ERC20(pool.token0());
            token1 = ERC20(pool.token1());
            // Calculate current sqrtPrice.
            (sqrtPriceX96, , , , , , ) = pool.slot0();
            position = tracker.getTokenAtIndex(caller, address(pool), index);
        }

        if (position == 0 || positionManager.ownerOf(position) != caller) return (0, 0, position, token0, token1);

        // If cellar does not own any UniV3 positions it has no assets in UniV3.
        if (position == 0) return (0, 0, position, token0, token1);

        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = positionManager.positions(position);

        // Skip LP tokens if there is no liquidity in the position.
        if (liquidity == 0) return (0, 0, position, token0, token1);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );

        // TODO we could add a check here to make sure the pool tick is not being manipulated. Like if we use the
        // Chainlink price we could derive a safe pool tick.
        // But I haven't found any scenarios where the pool tick being manipulated led to loss of Cellar funds, only gains.

        return (
            amount0 + Cellar(caller).priceRouter().getValue(token1, amount1, token0),
            liquidity,
            position,
            token0,
            token1
        );
    }
}
