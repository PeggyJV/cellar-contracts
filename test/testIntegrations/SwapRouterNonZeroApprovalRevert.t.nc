// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Registry } from "src/Registry.sol";
import { ICellarV1_5 as Cellar } from "src/interfaces/ICellarV1_5.sol";
import { ERC20 } from "src/base/ERC20.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { ICellarRouterV1_5 as CellarRouter } from "src/interfaces/ICellarRouterV1_5.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract SwapRouterIntegrationTest is Test {
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private strategist = 0x13FBB7e817e5347ce4ae39c3dff1E6705746DCdC;

    address private uniswapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private zeroXExchangeProxy = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    Cellar private cellarTrend;
    Cellar private cellarMomentum;
    Registry private registry;
    SwapRouter private swapRouter;
    CellarRouter private cellarRouter;

    function setUp() external {
        cellarTrend = Cellar(0x6b7f87279982d919Bbf85182DDeAB179B366D8f2);
        cellarMomentum = Cellar(0x6E2dAc3b9E9ADc0CbbaE2D0B9Fd81952a8D33872);
        cellarRouter = CellarRouter(0x1D90366B0154fBcB5101c06a39c25D26cB48e889);

        registry = Registry(0xDffa1443a72Fd3f4e935b93d0C3BFf8FE80cE083);

        swapRouter = new SwapRouter(IUniswapV2Router(uniswapV2Router), IUniswapV3Router(uniswapV3Router));
    }

    function testAttackVector() external {
        if (block.number < 15870000) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 15870000.");
            return;
        }
        // Attacker performs a bad swap with low liquidity pool to stop cellars from rebalancing.
        SwapRouter oldRouter = SwapRouter(registry.getAddress(1));
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(oldRouter), assets);

        // Attacker chooses the USDC/stETH pool because it has low liquidity.
        ERC20 stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(stETH);

        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3%

        bytes memory swapData = abi.encode(path, poolFees, assets, 0);

        // Attacker performs bad swap which leaves SwapRouter with a nonzero USDC approval for the UniV3 router.
        oldRouter.swap(SwapRouter.Exchange.UNIV3, swapData, address(this), USDC, stETH);
        assertTrue(
            USDC.allowance(address(oldRouter), address(swapRouter.uniswapV3Router())) > 0,
            "Uniswap V3 Router should have a non zero approval."
        );

        // Now if cellars try to sell USDC to a UniV3 pair, the TX will revert.
        vm.startPrank(gravityBridge);
        path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WBTC);
        poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3% fee
        uint256 amount = 10_000e6;
        bytes memory params = abi.encode(path, poolFees, amount, 0);
        vm.expectRevert(bytes("SafeERC20: approve from non-zero to non-zero allowance"));
        cellarTrend.rebalance(address(USDC), address(WBTC), amount, uint8(SwapRouter.Exchange.UNIV3), params);

        vm.expectRevert(bytes("SafeERC20: approve from non-zero to non-zero allowance"));
        cellarMomentum.rebalance(address(USDC), address(WBTC), amount, uint8(SwapRouter.Exchange.UNIV3), params);
        vm.stopPrank();
    }

    function testAttackVectorIsMitigated() external {
        if (block.number < 15870000) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 15870000.");
            return;
        }
        // Update registry with new Swap Router.
        vm.prank(sommMultiSig);
        registry.setAddress(1, address(swapRouter));

        // Attacker tries to perform a bad swap with low liquidity pool to stop cellars from rebalancing.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(swapRouter), assets);

        // Attacker chooses the USDC/stETH pool because it has low liquidity.
        ERC20 stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(stETH);

        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3%

        bytes memory swapData = abi.encode(path, poolFees, assets, 0);

        // Attackers swap reverts because of the unused approval.
        vm.expectRevert(bytes(abi.encodeWithSelector(SwapRouter.SwapRouter__UnusedApproval.selector)));
        swapRouter.swap(SwapRouter.Exchange.UNIV3, swapData, address(this), USDC, stETH);

        // Cellars are still able to make swaps.
        vm.startPrank(gravityBridge);
        path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WBTC);
        poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3% fee
        uint256 amount = 10_000e6;
        bytes memory params = abi.encode(path, poolFees, amount, 0);

        // Trend Cellar is able to swap.
        cellarTrend.rebalance(address(USDC), address(WBTC), amount, uint8(SwapRouter.Exchange.UNIV3), params);

        // Momumtum Cellar is able to swap.
        cellarMomentum.rebalance(address(USDC), address(WBTC), amount, uint8(SwapRouter.Exchange.UNIV3), params);
        vm.stopPrank();
    }

    function testCellars() external {
        if (block.number < 15870000) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 15870000.");
            return;
        }
        _testCellar(cellarTrend);
        _testCellar(cellarMomentum);
    }

    function _testCellar(Cellar cellar) internal {
        // Update registry with new Swap Router.
        vm.prank(sommMultiSig);
        registry.setAddress(1, address(swapRouter));

        uint256 userAssets = 10_000e6;
        //  Have user deposit into Cellar
        uint256 currentTotalAssets = cellar.totalAssets();
        deal(address(USDC), address(this), userAssets);
        USDC.approve(address(cellar), userAssets);
        cellar.deposit(userAssets, address(this));
        assertEq(cellar.totalAssets(), currentTotalAssets + userAssets, "Total assets should equal 100,000 USDC.");
        // Use the Cellar Router to Deposit and Swap into the cellar.
        userAssets = 10_000e18;
        currentTotalAssets = cellar.totalAssets();
        deal(address(DAI), address(this), userAssets);
        DAI.approve(address(cellarRouter), userAssets);
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 100; // 0.01%
        bytes memory swapData = abi.encode(path, poolFees, userAssets, 0);
        cellarRouter.depositAndSwap(
            address(cellar),
            uint8(SwapRouter.Exchange.UNIV3),
            swapData,
            userAssets,
            address(DAI)
        );
        currentTotalAssets = cellar.totalAssets();

        // Strategist swaps 10,000 USDC for wBTC on UniV2.
        vm.startPrank(gravityBridge);
        path = new address[](3);
        path[0] = address(USDC);
        path[1] = address(WETH);
        path[2] = address(WBTC);
        uint256 amount = 10_000e6;
        bytes memory params = abi.encode(path, amount, 0);
        cellar.rebalance(address(USDC), address(WBTC), amount, uint8(SwapRouter.Exchange.UNIV2), params);
        vm.stopPrank();

        // Strategist swaps 10,000 USDC for wBTC on UniV3.
        vm.startPrank(gravityBridge);
        path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WBTC);
        poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3% fee
        amount = 10_000e6;
        params = abi.encode(path, poolFees, amount, 0);
        cellar.rebalance(address(USDC), address(WBTC), amount, uint8(SwapRouter.Exchange.UNIV3), params);
        vm.stopPrank();

        assertApproxEqRel(
            cellar.totalAssets(),
            currentTotalAssets,
            0.005e18,
            "Total assets should approximately be equal to 100,000 USDC."
        );

        // Advance blocks forward to unlock shares.
        vm.roll(block.number + cellar.shareLockPeriod());

        // Have a user exit the cellar using Cellar Router.
        uint8[] memory exchanges = new uint8[](1);
        bytes[] memory swapDatas = new bytes[](1);
        exchanges[0] = uint8(SwapRouter.Exchange.UNIV3);
        path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(DAI);
        poolFees = new uint24[](1);
        poolFees[0] = 100; // 0.01%
        swapDatas[0] = abi.encode(path, poolFees, 1_000e6, 0);
        userAssets = cellar.maxWithdraw(address(this));
        cellar.approve(address(cellarRouter), type(uint256).max);
        cellarRouter.withdrawAndSwap(address(cellar), exchanges, swapDatas, userAssets, address(this));
    }
}
