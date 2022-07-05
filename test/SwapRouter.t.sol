// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IUniswapV3Router as UniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { IUniswapV2Router02 as UniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { ICurveSwaps } from "src/interfaces/ICurveSwaps.sol";
import { IBalancerExchangeProxy } from "src/interfaces/BalancerInterfaces.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract SwapRouterTest is Test {
    using Math for uint256;

    SwapRouter private swapRouter;

    uint256 private constant privateKey0 = 0xABCD;
    uint256 private constant privateKey1 = 0xBEEF;
    address private sender = vm.addr(privateKey0);
    address private reciever = vm.addr(privateKey1);

    // Mainnet contracts:
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant curveRegistryExchange = 0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7;
    address private constant curveStableSwap3Pool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address private constant balancerExchangeProxy = 0x3E66B66Fd1d0b02fDa6C811Da9E0547970DB2f21;
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private AAVE = ERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);

    function setUp() public {
        swapRouter = new SwapRouter(
            UniswapV2Router(uniV2Router),
            UniswapV3Router(uniV3Router),
            ICurveSwaps(curveRegistryExchange),
            IBalancerExchangeProxy(balancerExchangeProxy)
        );

        vm.startPrank(sender);
    }

    // ======================================= SWAP TESTS =======================================

    function testSimpleSwapV2(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        // Test swap.
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        bytes memory swapData = abi.encode(path, assets, 0, sender);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.UNIV2, swapData, reciever);

        assertTrue(DAI.balanceOf(sender) == 0, "DAI Balance of sender should be 0");
        assertTrue(WETH.balanceOf(reciever) > 0, "WETH Balance of Reciever should be greater than 0");
        assertEq(out, WETH.balanceOf(reciever), "Amount Out should equal WETH Balance of reciever");
    }

    function testMultiSwapV2(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](3);
        path[0] = address(DAI);
        path[1] = address(WETH);
        path[2] = address(USDC);

        // Test swap.
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        bytes memory swapData = abi.encode(path, assets, 0, sender);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.UNIV2, swapData, reciever);

        assertTrue(DAI.balanceOf(sender) == 0, "DAI Balance of sender should be 0");
        assertTrue(USDC.balanceOf(reciever) > 0, "USDC Balance of Reciever should be greater than 0");
        assertEq(out, USDC.balanceOf(reciever), "Amount Out should equal USDC Balance of reciever");
    }

    function testSimpleSwapV3(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        // Specify the pool fee tiers to use for each swap, 0.3% for DAI <-> WETH.
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        // Test swap.
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        bytes memory swapData = abi.encode(path, poolFees, assets, 0, sender);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.UNIV3, swapData, reciever);

        assertTrue(DAI.balanceOf(sender) == 0, "DAI Balance of sender should be 0");
        assertTrue(WETH.balanceOf(reciever) > 0, "WETH Balance of Reciever should be greater than 0");
        assertEq(out, WETH.balanceOf(reciever), "Amount Out should equal WETH Balance of reciever");
    }

    function testMultiSwapV3(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](3);
        path[0] = address(DAI);
        path[1] = address(WETH);
        path[2] = address(USDC);

        // Specify the pool fee tiers to use for each swap
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000; // 0.3%
        poolFees[1] = 100; // 0.01%

        // Test swap.
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        bytes memory swapData = abi.encode(path, poolFees, assets, 0, sender);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.UNIV3, swapData, reciever);

        assertTrue(DAI.balanceOf(sender) == 0, "DAI Balance of sender should be 0");
        assertTrue(USDC.balanceOf(reciever) > 0, "USDC Balance of Reciever should be greater than 0");
        assertEq(out, USDC.balanceOf(reciever), "Amount Out should equal USDC Balance of reciever");
    }

    function testCurveSwap(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets = bound(assets, 1e18, type(uint112).max);

        // Test swap.
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);

        address[9] memory route;
        route[0] = address(DAI);
        route[1] = curveStableSwap3Pool;
        route[2] = address(USDC);

        // [i, j, swap type], where i and j: 0 - DAI, 1 - USDC, 2 - USDT; swap type: 1 - for a stableswap `exchange`
        uint256[3][4] memory swapParams;
        swapParams[0][0] = 0;
        swapParams[0][1] = 1;
        swapParams[0][2] = 1;

        bytes memory swapData = abi.encode(route, swapParams, DAI, USDC, assets, 0, sender, reciever);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.CURVE, swapData);

        assertTrue(DAI.balanceOf(sender) == 0, "DAI Balance of sender should be 0");
        assertTrue(USDC.balanceOf(reciever) > 0, "USDC Balance of Reciever should be greater than 0");
        assertEq(out, USDC.balanceOf(reciever), "Amount Out should equal USDC Balance of reciever");
    }

    function testBalancerSwap(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets = bound(assets, 1e18, 100000e18);

        // Test swap.
        deal(address(AAVE), sender, assets, true);
        AAVE.approve(address(swapRouter), assets);

        bytes memory swapData = abi.encode(0xC697051d1C6296C24aE3bceF39acA743861D9A81, AAVE, WETH, assets, 0, sender, reciever);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.BALANCERV2, swapData);

        assertTrue(AAVE.balanceOf(sender) == 0, "DAI Balance of sender should be 0");
        assertTrue(WETH.balanceOf(reciever) > 0, "WETH Balance of Reciever should be greater than 0");
        assertEq(out, WETH.balanceOf(reciever), "Amount Out should equal WETH Balance of reciever");
    }
}
