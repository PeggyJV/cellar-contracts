// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { MockCellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, SwapRouter, IGravity } from "src/Registry.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockExchange } from "src/mocks/MockExchange.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarTest is Test {
    using SafeTransferLib for ERC20;
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
    }

    // ============================================ HELPER FUNCTIONS ============================================

    // For some reason `deal(address(position.asset()), address(position), assets)` isn't working at
    // the time of writing but dealing to this address is. This is a workaround.
    function simulateGains(address position, uint256 assets) internal {
        ERC20 asset = ERC4626(position).asset();

        deal(address(asset), address(this), assets);

        asset.safeTransfer(position, assets);
    }

    function simulateLoss(address position, uint256 assets) internal {
        ERC20 asset = ERC4626(position).asset();

        vm.prank(position);
        asset.approve(address(this), assets);

        asset.safeTransferFrom(position, address(1), assets);
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
        cellar.depositIntoPosition(address(wethCLR), 1e18);

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
        cellar.depositIntoPosition(address(wethCLR), 1e18);
        cellar.depositIntoPosition(address(wbtcCLR), 1e8);

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

    // =========================================== ACCRUE TEST ===========================================

    // TODO: DRY this up.
    // TODO: Fuzz.
    // TODO: Add checks that highwatermarks for each position were updated.

    function testAccrueWithPositivePerformance() external {
        // Initialize position balances.
        cellar.depositIntoPosition(address(usdcCLR), 1000e6, address(this)); // $1000
        cellar.depositIntoPosition(address(wethCLR), 1e18, address(this)); // $2000
        cellar.depositIntoPosition(address(wbtcCLR), 1e8, address(this)); // $30,000

        assertEq(cellar.totalAssets(), 33_000e6, "Should have initialized total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), 33_000e18, "Should have initialized total shares.");

        // Simulate gains.
        simulateGains(address(usdcCLR), 500e6); // $500
        simulateGains(address(wethCLR), 0.5e18); // $1000
        simulateGains(address(wbtcCLR), 0.5e8); // $15,000

        assertEq(cellar.totalAssets(), 49_500e6, "Should have updated total assets with gains.");

        cellar.accrue();

        assertApproxEqAbs(
            cellar.convertToAssets(cellar.balanceOf(address(cellar))),
            1650e6,
            1, // May be off by 1 due to rounding.
            "Should have minted performance fees to cellar."
        );
    }

    function testAccrueWithNegativePerformance() external {
        // Initialize position balances.
        cellar.depositIntoPosition(address(usdcCLR), 1000e6, address(this)); // $1000
        cellar.depositIntoPosition(address(wethCLR), 1e18, address(this)); // $2000
        cellar.depositIntoPosition(address(wbtcCLR), 1e8, address(this)); // $30,000

        assertEq(cellar.totalAssets(), 33_000e6, "Should have initialized total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), 33_000e18, "Should have initialized total shares.");

        // Simulate losses.
        simulateLoss(address(usdcCLR), 500e6); // -$500
        simulateLoss(address(wethCLR), 0.5e18); // -$1000
        simulateLoss(address(wbtcCLR), 0.5e8); // -$15,000

        assertEq(cellar.totalAssets(), 16_500e6, "Should have updated total assets with losses.");

        cellar.accrue();

        assertEq(
            cellar.convertToAssets(cellar.balanceOf(address(cellar))),
            0,
            "Should have minted no performance fees to cellar."
        );
    }

    function testAccrueWithNoPerformance() external {
        // Initialize position balances.
        cellar.depositIntoPosition(address(usdcCLR), 1000e6, address(this)); // $1000
        cellar.depositIntoPosition(address(wethCLR), 1e18, address(this)); // $2000
        cellar.depositIntoPosition(address(wbtcCLR), 1e8, address(this)); // $30,000

        assertEq(cellar.totalAssets(), 33_000e6, "Should have initialized total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), 33_000e18, "Should have initialized total shares.");

        cellar.accrue();

        assertEq(
            cellar.convertToAssets(cellar.balanceOf(address(cellar))),
            0,
            "Should have minted no performance fees to cellar."
        );
    }

    function testAccrueDepositsAndWithdrawsAreNotCountedAsYield(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        // Deposit into cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        cellar.accrue();
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have counted deposit into cellar as yield.");

        // Deposit assets from holding pool to USDC cellar position
        cellar.rebalance(
            ERC4626(address(cellar)),
            ERC4626(address(usdcCLR)),
            assets,
            SwapRouter.Exchange.UNIV2, // Does not matter, no swap is involved.
            abi.encode(0) // Does not matter, no swap is involved.
        );

        cellar.accrue();
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have counted deposit into position as yield.");

        // Withdraw some assets from USDC cellar position to holding position.
        cellar.rebalance(
            ERC4626(address(usdcCLR)),
            ERC4626(address(cellar)),
            assets / 2,
            SwapRouter.Exchange.UNIV2, // Does not matter, no swap is involved.
            abi.encode(0) // Does not matter, no swap is involved.
        );

        cellar.accrue();
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have counted withdrawals from position as yield.");

        // Withdraw assets from holding pool and USDC cellar position.
        cellar.withdrawFromPositions(assets, address(this), address(this));

        cellar.accrue();
        assertEq(
            cellar.balanceOf(address(cellar)),
            0,
            "Should not have counted withdrawals from holdings and position as yield."
        );
    }
}
