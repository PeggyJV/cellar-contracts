// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { MockCellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, SwapRouter, IGravity } from "src/Registry.sol";
import { IUniswapV2Router, IUniswapV3Router } from "src/modules/SwapRouter.sol";
import { MockExchange } from "src/mocks/MockExchange.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";

import { CellarRouter } from "src/CellarRouter.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarTest is Test {
    using Math for uint256;

    MockCellar private cellar;
    MockGravity private gravity;

    MockExchange private exchange;
    MockPriceRouter private priceRouter;
    SwapRouter private swapRouter;

    Registry private registry;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    MockERC4626 private usdcCLR;

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    MockERC4626 private wethCLR;

    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    MockERC4626 private wbtcCLR;

    //========================= CRISPY TEMPORARY ==========================
    // Mainnet contracts:
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    CellarRouter private cellarRouter;

    function setUp() external {
        usdcCLR = new MockERC4626(USDC, "USDC Cellar LP Token", "USDC-CLR", 6);
        vm.label(address(usdcCLR), "usdcCLR");

        wethCLR = new MockERC4626(WETH, "WETH Cellar LP Token", "WETH-CLR", 18);
        vm.label(address(wethCLR), "wethCLR");

        wbtcCLR = new MockERC4626(WBTC, "WBTC Cellar LP Token", "WBTC-CLR", 8);
        vm.label(address(wbtcCLR), "wbtcCLR");

        // Setup Registry and modules:
        priceRouter = new MockPriceRouter();
        exchange = new MockExchange(priceRouter);
        swapRouter = new SwapRouter(IUniswapV2Router(address(exchange)), IUniswapV3Router(address(exchange)));
        gravity = new MockGravity();

        registry = new Registry(
            SwapRouter(address(swapRouter)),
            PriceRouter(address(priceRouter)),
            IGravity(address(gravity))
        );

        // Setup exchange rates:
        // USDC Simulated Price: $1
        // WETH Simulated Price: $2000
        // WBTC Simulated Price: $30,000

        priceRouter.setExchangeRate(USDC, USDC, 1e6);
        priceRouter.setExchangeRate(WETH, WETH, 1e18);
        priceRouter.setExchangeRate(WBTC, WBTC, 1e8);

        priceRouter.setExchangeRate(USDC, WETH, 0.0005e18);
        priceRouter.setExchangeRate(WETH, USDC, 2000e6);

        priceRouter.setExchangeRate(USDC, WBTC, 0.000033e8);
        priceRouter.setExchangeRate(WBTC, USDC, 30_000e6);

        priceRouter.setExchangeRate(WETH, WBTC, 0.06666666e8);
        priceRouter.setExchangeRate(WBTC, WETH, 15e18);

        // Setup Cellar:
        address[] memory positions = new address[](3);
        positions[0] = address(usdcCLR);
        positions[1] = address(wethCLR);
        positions[2] = address(wbtcCLR);

        cellar = new MockCellar(registry, USDC, positions, "Multiposition Cellar LP Token", "multiposition-CLR");
        vm.label(address(cellar), "cellar");

        // Transfer ownership to this contract for testing.
        vm.prank(address(registry.gravityBridge()));
        cellar.transferOwnership(address(this));

        // Mint enough liquidity to swap router for swaps.
        deal(address(USDC), address(exchange), type(uint224).max);
        deal(address(WETH), address(exchange), type(uint224).max);
        deal(address(WBTC), address(exchange), type(uint224).max);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        WETH.approve(address(cellar), type(uint256).max);
        WBTC.approve(address(cellar), type(uint256).max);

        cellarRouter = new CellarRouter(IUniswapV3Router(address(exchange)), IUniswapV2Router(address(exchange)));
    }

    // ========================================= DEPOSIT/WITHDRAW TEST =========================================

    function testDepositAndWithdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        deal(address(USDC), address(this), assets);

        // Test single deposit.
        uint256 shares = cellar.deposit(assets, address(this));

        assertEq(shares, assets.changeDecimals(6, 18), "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assets), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        assertEq(cellar.totalAssets(), 0, "Should have updated total assets with assets withdrawn.");
        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testWithdrawFromPositions() external {
        cellar.increasePositionBalance(address(wethCLR), 1e18);

        assertEq(cellar.totalAssets(), 2000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(1000e6));

        // Withdraw from position.
        (uint256 shares, ERC20[] memory receivedAssets, uint256[] memory amountsOut) = cellar.withdrawFromPositions(
            1000e6,
            address(this),
            address(this)
        );

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 1000e18, "Should returned all redeemed shares.");
        assertEq(receivedAssets.length, 1, "Should have received one asset.");
        assertEq(amountsOut.length, 1, "Should have gotten out one amount.");
        assertEq(address(receivedAssets[0]), address(WETH), "Should have received WETH.");
        assertEq(amountsOut[0], 0.5e18, "Should have gotten out 0.5 WETH.");
        assertEq(WETH.balanceOf(address(this)), 0.5e18, "Should have transferred position balance to user.");
        assertEq(cellar.totalAssets(), 1000e6, "Should have updated cellar total assets.");
    }

    function testWithdrawFromPositionsCompletely() external {
        cellar.increasePositionBalance(address(wethCLR), 1e18);
        cellar.increasePositionBalance(address(wbtcCLR), 1e8);

        assertEq(cellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(32_000e6));

        // Withdraw from position.
        (uint256 shares, ERC20[] memory receivedAssets, uint256[] memory amountsOut) = cellar.withdrawFromPositions(
            32_000e6,
            address(this),
            address(this)
        );

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 32_000e18, "Should returned all redeemed shares.");
        assertEq(receivedAssets.length, 2, "Should have received two assets.");
        assertEq(amountsOut.length, 2, "Should have gotten out two amount.");
        assertEq(address(receivedAssets[0]), address(WETH), "Should have received WETH.");
        assertEq(address(receivedAssets[1]), address(WBTC), "Should have received WBTC.");
        assertEq(amountsOut[0], 1e18, "Should have gotten out 1 WETH.");
        assertEq(amountsOut[1], 1e8, "Should have gotten out 1 WBTC.");
        assertEq(WETH.balanceOf(address(this)), 1e18, "Should have transferred position balance to user.");
        assertEq(WBTC.balanceOf(address(this)), 1e8, "Should have transferred position balance to user.");
        assertEq(cellar.totalAssets(), 0, "Should have emptied cellar.");
    }

    function testWithdrawFromPositionsIntoSingleAssetWTwoSwaps() external {
        cellar.increasePositionBalance(address(wethCLR), 1e18);
        cellar.increasePositionBalance(address(wbtcCLR), 1e8);

        assertEq(cellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(32_000e6));

        //create paths
        address[][] memory paths = new address[][](2);
        paths[0] = new address[](2);
        paths[0][0] = address(WETH);
        paths[0][1] = address(USDC);
        paths[1] = new address[](2);
        paths[1][0] = address(WBTC);
        paths[1][1] = address(USDC);
        uint24[][] memory poolFees = new uint24[][](2);
        poolFees[0] = new uint24[](0);
        poolFees[1] = new uint24[](0);
        uint256 assets = 32_000e6;
        uint256[] memory minOuts = new uint256[](2);
        minOuts[0] = 0;
        minOuts[1] = 0;

        cellar.approve(address(cellarRouter), type(uint256).max);
        //cellarRouter.withdrawFromPositionsIntoSingleAsset(cellar, paths, poolFees, assets, minOuts, address(this));

        //assertEq(USDC.balanceOf(address(this)), 30_400e6, "Did not recieve expected assets");
    }

    /**
     * @notice if the asset wanted is an asset given, then it should just be added to the output with no swaps needed
     */
    function testWithdrawFromPositionsIntoSingleAssetWOneSwap() external {
        cellar.increasePositionBalance(address(wethCLR), 1e18);
        cellar.increasePositionBalance(address(wbtcCLR), 1e8);

        assertEq(cellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(32_000e6));

        //create paths
        address[][] memory paths = new address[][](2);
        paths[0] = new address[](1);
        paths[0][0] = address(WETH);
        paths[1] = new address[](2);
        paths[1][0] = address(WBTC);
        paths[1][1] = address(WETH);
        uint24[][] memory poolFees = new uint24[][](2);
        poolFees[0] = new uint24[](0);
        poolFees[1] = new uint24[](0);
        uint256 assets = 32_000e6;
        uint256[] memory minOuts = new uint256[](2);
        minOuts[0] = 0;
        minOuts[1] = 0;

        cellar.approve(address(cellarRouter), type(uint256).max);
        //cellarRouter.withdrawFromPositionsIntoSingleAsset(cellar, paths, poolFees, assets, minOuts, address(this));
        //assertEq(WETH.balanceOf(address(this)), 15.25e18, "Did not recieve expected assets");
    }
}
