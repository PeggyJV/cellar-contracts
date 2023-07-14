// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import "@uniswapV3C/libraries/FixedPoint128.sol";
import "@uniswapV3C/libraries/FullMath.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract FixRYLINK is Test {
    using Math for uint256;

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private controller = 0xaDa78a5E01325B91Bc7879a63c309F7D54d42950;

    IUniswapV3Factory internal factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    CellarInitializableV2_2 private rye = CellarInitializableV2_2(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 public wstETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    address public erc20Adaptor = 0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE;

    UniswapV3Adaptor private uniswapV3Adaptor = UniswapV3Adaptor(0x92611574EC9BC13C6137917481dab7BB7b173c9b);
    address public oldUniswapV3Adaptor = 0x0bD9a2c1917E3a932A4a712AEE38FF63D35733Fb;

    uint32 oldRethWethPosition = 111;
    uint32 oldCbethWethPosition = 110;
    uint32 oldWstethWethPosition = 140;

    uint32 newRethWethPosition;
    uint32 newCbethWethPosition;
    uint32 newWstethWethPosition;

    modifier checkBlockNumber() {
        if (block.number < 17687832) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17687832.");
            return;
        }
        _;
    }

    function testRealYieldEth() external checkBlockNumber {
        // TODO make sure strategists can rebalance out of old positions.
        // then enter new ones
        // Distrust old adaptor and position in registry.
        // Then add new new positions and adaptor.
        vm.startPrank(multisig);
        registry.distrustPosition(oldRethWethPosition);
        registry.distrustPosition(oldCbethWethPosition);
        registry.distrustPosition(oldWstethWethPosition);
        registry.distrustAdaptor(oldUniswapV3Adaptor);

        registry.trustAdaptor(address(uniswapV3Adaptor));
        newRethWethPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(rETH, WETH));
        newCbethWethPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(cbETH, WETH));
        newWstethWethPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(wstETH, WETH));
        vm.stopPrank();

        // Have Real Yield Eth rebalance so it does not have any UniV3 positions.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToCloseLP(address(rye), 0);
            data[0] = Cellar.AdaptorCall({ adaptor: address(oldUniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToCloseLP(address(rye), 1);
            data[1] = Cellar.AdaptorCall({ adaptor: address(oldUniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToCloseLP(address(rye), 2);
            data[2] = Cellar.AdaptorCall({ adaptor: address(oldUniswapV3Adaptor), callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);

        // Make sure we have zero uniV3 positions now.
        assertEq(positionManager.balanceOf(address(rye)), 0, "RYE should own 0 UniV3 positions now.");

        // Strategist can now remove old uniswap positions and remove them from the catalogue.
        vm.startPrank(gravityBridge);
        rye.removePosition(8, false);
        rye.removePosition(2, false);
        rye.removePosition(1, false);
        rye.removePositionFromCatalogue(oldRethWethPosition);
        rye.removePositionFromCatalogue(oldCbethWethPosition);
        rye.removePositionFromCatalogue(oldWstethWethPosition);
        rye.removeAdaptorFromCatalogue(oldUniswapV3Adaptor);
        vm.stopPrank();

        // Steward is upgraded to allow strategist to enter new uniswap V3 positions.
        vm.startPrank(gravityBridge);
        rye.addAdaptorToCatalogue(address(uniswapV3Adaptor));
        rye.addPositionToCatalogue(newRethWethPosition);
        rye.addPositionToCatalogue(newCbethWethPosition);
        rye.addPositionToCatalogue(newWstethWethPosition);
        rye.addPosition(8, newRethWethPosition, abi.encode(0), false);
        rye.addPosition(8, newCbethWethPosition, abi.encode(0), false);
        rye.addPosition(8, newWstethWethPosition, abi.encode(0), false);
        vm.stopPrank();

        // Mint some WSTETH, and WETH to the Cellar so it has some to enter WSTETH/WETH UniV3 LP.
        deal(address(wstETH), address(rye), 1_000e18);
        deal(address(cbETH), address(rye), 1_000e18);
        deal(address(rETH), address(rye), 1_000e18);
        deal(address(WETH), address(rye), 4_000e18);

        uint256 totalAssetsBefore = rye.totalAssets();

        // Strategist can now rebalance into UniV3.
        data = new Cellar.AdaptorCall[](3);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(rETH, WETH, 100, 1_000e18, 1_000e18, 100);
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(cbETH, WETH, 500, 1_000e18, 1_000e18, 100);
            data[1] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(wstETH, WETH, 100, 1_000e18, 1_000e18, 100);
            data[2] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);

        uint256 totalAssetsAfter = rye.totalAssets();

        // Make sure totalAssets is roughly the same.
        assertApproxEqRel(
            totalAssetsBefore,
            totalAssetsAfter,
            0.0001e18,
            "Total Assets should not have deviated too much."
        );

        // Make sure we have three uniV3 positions now.
        assertEq(positionManager.balanceOf(address(rye)), 3, "RYE should own 3 UniV3 positions now.");
        assertLt(WETH.balanceOf(address(rye)), 4_000e18, "RYE WETH Balance should have decreased.");
        assertLt(wstETH.balanceOf(address(rye)), 1_000e18, "RYE wstETH Balance should have decreased.");
        assertLt(rETH.balanceOf(address(rye)), 1_000e18, "RYE rETH Balance should have decreased.");
        assertLt(cbETH.balanceOf(address(rye)), 1_000e18, "RYE cbETH Balance should have decreased.");
    }

    // ========================================= HELPER FUNCTIONS =========================================
    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }

    /**
     * @notice Get the upper and lower tick around token0, token1.
     * @param token0 The 0th Token in the UniV3 Pair
     * @param token1 The 1st Token in the UniV3 Pair
     * @param fee The desired fee pool
     * @param size Dictates the amount of ticks liquidity will cover
     *             @dev Must be an even number
     * @param shift Allows the upper and lower tick to be moved up or down relative
     *              to current price. Useful for range orders.
     */
    function _getUpperAndLowerTick(
        ERC20 token0,
        ERC20 token1,
        uint24 fee,
        int24 size,
        int24 shift
    ) internal view returns (int24 lower, int24 upper) {
        uint256 price = priceRouter.getExchangeRate(token1, token0);
        uint256 ratioX192 = ((10 ** token1.decimals()) << 192) / (price);
        uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(ratioX192));
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        tick = tick + shift;

        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(address(token0), address(token1), fee));
        int24 spacing = pool.tickSpacing();
        lower = tick - (tick % spacing);
        lower = lower - ((spacing * size) / 2);
        upper = lower + spacing * size;
    }

    function _createBytesDataForSwap(
        ERC20 from,
        ERC20 to,
        uint24 poolFee,
        uint256 fromAmount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = poolFee;
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV3.selector, path, poolFees, fromAmount, 0);
    }

    function _createBytesDataToOpenLP(
        ERC20 token0,
        ERC20 token1,
        uint24 poolFee,
        uint256 amount0,
        uint256 amount1,
        int24 size
    ) internal view returns (bytes memory) {
        (int24 lower, int24 upper) = _getUpperAndLowerTick(token0, token1, poolFee, size, 0);
        return
            abi.encodeWithSelector(
                UniswapV3Adaptor.openPosition.selector,
                token0,
                token1,
                poolFee,
                amount0,
                amount1,
                0,
                0,
                lower,
                upper
            );
    }

    function _createBytesDataToCloseLP(address owner, uint256 index) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.closePosition.selector, tokenId, 0, 0);
    }

    function _createBytesDataToAddLP(
        address owner,
        uint256 index,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.addToPosition.selector, tokenId, amount0, amount1, 0, 0);
    }

    function _createBytesDataToTakeLP(
        address owner,
        uint256 index,
        uint256 liquidityPer,
        bool takeFees
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        uint128 liquidity;
        if (liquidityPer >= 1e18) liquidity = type(uint128).max;
        else {
            (, , , , , , , uint128 positionLiquidity, , , , ) = positionManager.positions(tokenId);
            liquidity = uint128((positionLiquidity * liquidityPer) / 1e18);
        }
        return abi.encodeWithSelector(UniswapV3Adaptor.takeFromPosition.selector, tokenId, liquidity, 0, 0, takeFees);
    }

    function _createBytesDataToCollectFees(
        address owner,
        uint256 index,
        uint128 amount0,
        uint128 amount1
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.collectFees.selector, tokenId, amount0, amount1);
    }

    function _createBytesDataToPurgePosition(address owner, uint256 index) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.purgeSinglePosition.selector, tokenId);
    }

    function _createBytesDataToPurgeAllZeroLiquidityPosition(
        ERC20 token0,
        ERC20 token1
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(UniswapV3Adaptor.purgeAllZeroLiquidityPositions.selector, token0, token1);
    }

    function _createBytesDataToRemoveTrackedPositionNotOwned(
        uint256 id,
        ERC20 token0,
        ERC20 token1
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(UniswapV3Adaptor.removeUnOwnedPositionFromTracker.selector, id, token0, token1);
    }

    function _createBytesDataToOpenRangeOrder(
        ERC20 token0,
        ERC20 token1,
        uint24 poolFee,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (bytes memory) {
        int24 lower;
        int24 upper;
        if (amount0 > 0) {
            (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, 100);
        } else {
            (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, -100);
        }

        return
            abi.encodeWithSelector(
                UniswapV3Adaptor.openPosition.selector,
                token0,
                token1,
                poolFee,
                amount0,
                amount1,
                0,
                0,
                lower,
                upper
            );
    }
}
