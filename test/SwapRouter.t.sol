// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IUniswapV3Router as UniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { IUniswapV2Router02 as UniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";

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
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        swapRouter = new SwapRouter(UniswapV2Router(uniV2Router), UniswapV3Router(uniV3Router));

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
        bytes memory swapData = abi.encode(path, assets, 0, reciever, sender);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.UNIV2, swapData);

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
        bytes memory swapData = abi.encode(path, assets, 0, reciever, sender);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.UNIV2, swapData);

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
        bytes memory swapData = abi.encode(path, poolFees, assets, 0, reciever, sender);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.UNIV3, swapData);

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
        bytes memory swapData = abi.encode(path, poolFees, assets, 0, reciever, sender);
        uint256 out = swapRouter.swap(SwapRouter.Exchange.UNIV3, swapData);

        assertTrue(DAI.balanceOf(sender) == 0, "DAI Balance of sender should be 0");
        assertTrue(USDC.balanceOf(reciever) > 0, "USDC Balance of Reciever should be greater than 0");
        assertEq(out, USDC.balanceOf(reciever), "Amount Out should equal USDC Balance of reciever");
    }
}
