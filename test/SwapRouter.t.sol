// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { IUniswapV3Router as UniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { IUniswapV2Router02 as UniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract SwapRouterTest is Test {
    using Math for uint256;

    SwapRouter private swapRouter;
    // Used to estimate the amount that should be received from swaps.
    PriceRouter private priceRouter;

    uint256 private constant privateKey0 = 0xABCD;
    uint256 private constant privateKey1 = 0xBEEF;
    address private sender = vm.addr(privateKey0);
    address private receiver = vm.addr(privateKey1);

    // Mainnet contracts:
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        swapRouter = new SwapRouter(UniswapV2Router(uniV2Router), UniswapV3Router(uniV3Router));
        priceRouter = new PriceRouter();

        priceRouter.addAsset(WETH, ERC20(Denominations.ETH), 0, 0, 0);
        priceRouter.addAsset(USDC, ERC20(address(0)), 0, 0, 0);
        priceRouter.addAsset(DAI, ERC20(address(0)), 0, 0, 0);

        vm.startPrank(sender);
    }

    // ================================ UNISWAP V2 TEST ================================

    function testSingleSwapUsingUniswapV2(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Specify single swap path from DAI -> WETH.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        // Test single swap.
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        bytes memory swapData = abi.encode(path, assets, 0);
        uint256 received = swapRouter.swap(SwapRouter.Exchange.UNIV2, swapData, receiver);

        // Estimate approximate amount that should of been received.
        uint256 expectedReceived = priceRouter.getValue(DAI, assets, WETH);

        assertEq(DAI.balanceOf(sender), 0, "Should have swapped all DAI");
        assertApproxEqRel(WETH.balanceOf(receiver), expectedReceived, 0.05e18, "Should have received USDC");
        assertEq(received, WETH.balanceOf(receiver), "Should return correct amount received");
    }

    function testMultiSwapUsingUniswapV2(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Specify multi-swap path from DAI -> WETH -> USDC.
        address[] memory path = new address[](3);
        path[0] = address(DAI);
        path[1] = address(WETH);
        path[2] = address(USDC);

        // Test multi-swap.
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        bytes memory swapData = abi.encode(path, assets, 0);
        uint256 received = swapRouter.swap(SwapRouter.Exchange.UNIV2, swapData, receiver);

        // Estimate approximate amount that should of been received.
        uint256 expectedReceived = priceRouter.getValue(DAI, assets, USDC);

        assertEq(DAI.balanceOf(sender), 0, "Should have swapped all DAI");
        assertApproxEqRel(USDC.balanceOf(receiver), expectedReceived, 0.05e18, "Should have received USDC");
        assertEq(received, USDC.balanceOf(receiver), "Should return correct amount received");
    }

    // ================================ UNISWAP V3 TEST ================================

    function testSingleSwapUsingUniswapV3(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Specify single swap path from DAI -> WETH.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        // Specify fee tiers for each swap.
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3%

        // Test multi-swap.
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        bytes memory swapData = abi.encode(path, poolFees, assets, 0);
        uint256 received = swapRouter.swap(SwapRouter.Exchange.UNIV3, swapData, receiver);

        // Estimate approximate amount that should of been received.
        uint256 expectedReceived = priceRouter.getValue(DAI, assets, WETH);

        assertEq(DAI.balanceOf(sender), 0, "Should have swapped all DAI");
        assertApproxEqRel(WETH.balanceOf(receiver), expectedReceived, 0.05e18, "Should have received WETH");
        assertEq(received, WETH.balanceOf(receiver), "Should return correct amount received");
    }

    function testMultiSwapUsingUniswapV3(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Specify multi-swap path from DAI -> WETH -> USDC.
        address[] memory path = new address[](3);
        path[0] = address(DAI);
        path[1] = address(WETH);
        path[2] = address(USDC);

        // Specify fee tiers for each swap.
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000; // 0.3%
        poolFees[1] = 100; // 0.01%

        // Test multi-swap.
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        bytes memory swapData = abi.encode(path, poolFees, assets, 0);
        uint256 received = swapRouter.swap(SwapRouter.Exchange.UNIV3, swapData, receiver);

        // Estimate approximate amount that should of been received.
        uint256 expectedReceived = priceRouter.getValue(DAI, assets, USDC);

        assertEq(DAI.balanceOf(sender), 0, "Should have swapped all DAI");
        assertApproxEqRel(USDC.balanceOf(receiver), expectedReceived, 0.05e18, "Should have received USDC");
        assertEq(received, USDC.balanceOf(receiver), "Should return correct amount received");
    }
}
