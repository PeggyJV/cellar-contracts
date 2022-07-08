// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, SwapRouter, IGravity } from "src/base/Cellar.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockExchange } from "src/mocks/MockExchange.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { USR_InvalidPosition, USR_DirectDepositNotAllowedFor } from "src/Errors.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    MockCellar private cellar;
    MockCellar private simpleCellar;
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
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
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
        address[] memory positions = new address[](4);
        positions[0] = address(USDC);
        positions[1] = address(usdcCLR);
        positions[2] = address(wethCLR);
        positions[3] = address(wbtcCLR);

        Cellar.PositionType[] memory positionTypes = new Cellar.PositionType[](4);
        positionTypes[0] = Cellar.PositionType.ERC20;
        positionTypes[1] = Cellar.PositionType.ERC4626;
        positionTypes[2] = Cellar.PositionType.ERC4626;
        positionTypes[3] = Cellar.PositionType.ERC4626;

        cellar = new MockCellar(
            registry,
            USDC,
            positions,
            positionTypes,
            address(USDC),
            Cellar.WithdrawType.ORDERLY,
            "Multiposition Cellar LP Token",
            "multiposition-CLR"
        );
        vm.label(address(cellar), "cellar");

        // Mint enough liquidity to swap router for swaps.
        deal(address(USDC), address(exchange), type(uint224).max);
        deal(address(WETH), address(exchange), type(uint224).max);
        deal(address(WBTC), address(exchange), type(uint224).max);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        WETH.approve(address(cellar), type(uint256).max);
        WBTC.approve(address(cellar), type(uint256).max);

        // Setup Cellar:
        address[] memory simplePositions = new address[](2);
        simplePositions[0] = address(USDC);
        simplePositions[1] = address(WETH);

        Cellar.PositionType[] memory simplePositionTypes = new Cellar.PositionType[](2);
        simplePositionTypes[0] = Cellar.PositionType.ERC20;
        simplePositionTypes[1] = Cellar.PositionType.ERC20;

        simpleCellar = new MockCellar(
            registry,
            USDC,
            simplePositions,
            simplePositionTypes,
            address(USDC),
            Cellar.WithdrawType.ORDERLY,
            "USDC WETH Cellar LP Token",
            "usdc-weth-CLR"
        );

        // Approve simpleCellar to spend all assets.
        USDC.approve(address(simpleCellar), type(uint256).max);
        WETH.approve(address(simpleCellar), type(uint256).max);
        WBTC.approve(address(simpleCellar), type(uint256).max);

        //Allow direct deposits
        simpleCellar.allowPositionDirectDeposits(address(USDC));
        simpleCellar.allowPositionDirectDeposits(address(WETH));
        cellar.allowPositionDirectDeposits(address(wethCLR));
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

    function testDirectDepositERC20(uint256 assets) external {
        assets = bound(assets, 1e14, type(uint112).max);

        deal(address(WETH), address(this), assets);

        // Test direct deposit using ERC20.
        uint256 shares = simpleCellar.directDepositToPosition(address(WETH), assets, address(this));
        // Choose 6 decimals for easier rounding
        uint256 valueIn = (assets * 2000e6) / 1e18;
        assertEq(shares, valueIn.changeDecimals(6, 18), "Shares should euqal USDC value deposited into cellar.");
        assertEq(simpleCellar.maxWithdraw(address(this)), valueIn, "Withdrawable value out should equal value in.");
    }

    function testDirectDepositPosition(uint256 assets) external {
        assets = bound(assets, 1e14, type(uint112).max);

        deal(address(WETH), address(this), assets);

        // Test direct deposit into Cellar position using Cellar's underlying asset.
        uint256 shares = cellar.directDepositToPosition(address(wethCLR), assets, address(this));
        // Choose 6 decimals for easier rounding
        uint256 valueIn = (assets * 2000e6) / 1e18;
        assertEq(shares, valueIn.changeDecimals(6, 18), "Shares should euqal USDC value deposited into cellar.");
        assertEq(cellar.maxWithdraw(address(this)), valueIn, "Withdrawable value out should equal value in.");
    }

    function testDirectDepositCellarAsset(uint256 assets) external {
        assets = bound(assets, 1e6, type(uint72).max);

        deal(address(USDC), address(this), assets);

        // Test direct deposit into cellar  where cellar asset is the ERC20 being direct deposited.
        uint256 shares = simpleCellar.directDepositToPosition(address(USDC), assets, address(this));
        uint256 valueIn = assets;
        assertEq(shares, assets.changeDecimals(6, 18), "Shares should euqal USDC value deposited into cellar.");
        assertEq(simpleCellar.maxWithdraw(address(this)), valueIn, "Withdrawable value out should equal value in.");
    }

    function testDirectDepositInvalidPosition() external {
        uint256 assets = 1e8;

        deal(address(WBTC), address(this), assets);

        vm.expectRevert(abi.encodeWithSelector(USR_InvalidPosition.selector, address(wbtcCLR)));
        simpleCellar.directDepositToPosition(address(wbtcCLR), assets, address(this));
    }

    function testDirectDepositInvalidAsset() external {
        uint256 assets = 1e8;

        deal(address(WBTC), address(this), assets);

        vm.expectRevert(abi.encodeWithSelector(USR_InvalidPosition.selector, address(WBTC)));
        simpleCellar.directDepositToPosition(address(WBTC), assets, address(this));
    }

    function testDirectDepositNotAllowed() external {
        uint256 assets = 1e8;

        simpleCellar.stopPositionDirectDeposits(address(WETH));

        deal(address(WETH), address(this), assets);

        vm.expectRevert(abi.encodeWithSelector(USR_DirectDepositNotAllowedFor.selector, address(WETH)));
        simpleCellar.directDepositToPosition(address(WETH), assets, address(this));
    }

    function testWithdrawInOrder() external {
        cellar.depositIntoPosition(address(wethCLR), 1e18); // $2000
        cellar.depositIntoPosition(address(wbtcCLR), 1e8); // $30,000

        assertEq(cellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(32_000e6));

        // Withdraw from position.
        uint256 shares = cellar.withdraw(32_000e6, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 32_000e18, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 1e18, "Should have transferred position balance to user.");
        assertEq(WBTC.balanceOf(address(this)), 1e8, "Should have transferred position balance to user.");
        assertEq(cellar.totalAssets(), 0, "Should have emptied cellar.");
    }

    function testWithdrawInProportion() external {
        cellar.depositIntoPosition(address(wethCLR), 1e18); // $2000
        cellar.depositIntoPosition(address(wbtcCLR), 1e8); // $30,000

        assertEq(cellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");
        assertEq(cellar.totalSupply(), 32_000e18);

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(16_000e6));

        // Withdraw from position.
        cellar.setWithdrawType(Cellar.WithdrawType.PROPORTIONAL);
        uint256 shares = cellar.withdraw(16_000e6, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 16_000e18, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 0.5e18, "Should have transferred position balance to user.");
        assertEq(WBTC.balanceOf(address(this)), 0.5e8, "Should have transferred position balance to user.");
        assertEq(cellar.totalAssets(), 16_000e6, "Should have half of assets remaining in cellar.");
    }

    function testWithdrawWithDuplicateReceivedAssets() external {
        MockERC4626 wethVault = new MockERC4626(WETH, "WETH Vault LP Token", "WETH-VLT", 18);
        cellar.trustPosition(address(wethVault), Cellar.PositionType.ERC4626);
        cellar.pushPosition(address(wethVault));

        cellar.depositIntoPosition(address(wethCLR), 1e18); // $2000
        cellar.depositIntoPosition(address(wethVault), 0.5e18); // $1000

        assertEq(cellar.totalAssets(), 3000e6, "Should have updated total assets with assets deposited.");
        assertEq(cellar.totalSupply(), 3000e18);

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(3000e6));

        // Withdraw from position.
        uint256 shares = cellar.withdraw(3000e6, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 3000e18, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 1.5e18, "Should have transferred position balance to user.");
        assertEq(cellar.totalAssets(), 0, "Should have no assets remaining in cellar.");
    }

    // ========================================== REBALANCE TEST ==========================================

    // TODO: Test rebalancing to invalid position.

    function testRebalanceBetweenPositions(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        cellar.depositIntoPosition(address(usdcCLR), assets);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        uint256 assetsTo = cellar.rebalance(
            address(usdcCLR),
            address(wethCLR),
            assets,
            SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
            abi.encode(path, assets, 0, address(cellar), address(cellar))
        );

        assertEq(assetsTo, exchange.quote(assets, path), "Should received expected assets from swap.");
        assertEq(usdcCLR.balanceOf(address(cellar)), 0, "Should have rebalanced from position.");
        assertEq(wethCLR.balanceOf(address(cellar)), assetsTo, "Should have rebalanced to position.");
    }

    function testRebalanceToSamePosition(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        cellar.depositIntoPosition(address(usdcCLR), assets);

        uint256 assetsTo = cellar.rebalance(
            address(usdcCLR),
            address(usdcCLR),
            assets,
            SwapRouter.Exchange.UNIV2, // Will be ignored because no swap is necessary.
            abi.encode(0) // Will be ignored because no swap is necessary.
        );

        assertEq(assetsTo, assets, "Should received expected assets from swap.");
        assertEq(usdcCLR.balanceOf(address(cellar)), assets, "Should have not changed position balance.");
    }

    // =========================================== ACCRUE TEST ===========================================

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
            address(USDC),
            address(usdcCLR),
            assets,
            SwapRouter.Exchange.UNIV2, // Does not matter, no swap is involved.
            abi.encode(0) // Does not matter, no swap is involved.
        );

        cellar.accrue();
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have counted deposit into position as yield.");

        // Withdraw some assets from USDC cellar position to holding position.
        cellar.rebalance(
            address(usdcCLR),
            address(USDC),
            assets / 2,
            SwapRouter.Exchange.UNIV2, // Does not matter, no swap is involved.
            abi.encode(0) // Does not matter, no swap is involved.
        );

        cellar.accrue();
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have counted withdrawals from position as yield.");

        // Withdraw assets from holding pool and USDC cellar position.
        cellar.withdraw(assets, address(this), address(this));

        cellar.accrue();
        assertEq(
            cellar.balanceOf(address(cellar)),
            0,
            "Should not have counted withdrawals from holdings and position as yield."
        );
    }

    event Accrual(uint256 platformFees, uint256 performanceFees);

    function testAccrueUsesHighWatermark() external {
        // Initialize position balances.
        cellar.depositIntoPosition(address(usdcCLR), 1000e6, address(this)); // $1000
        cellar.depositIntoPosition(address(wethCLR), 1e18, address(this)); // $2000
        cellar.depositIntoPosition(address(wbtcCLR), 1e8, address(this)); // $30,000

        // Simulate gains.
        simulateGains(address(usdcCLR), 500e6); // $500
        simulateGains(address(wethCLR), 0.5e18); // $1000
        simulateGains(address(wbtcCLR), 0.5e8); // $15,000

        cellar.accrue();

        assertApproxEqAbs(
            cellar.convertToAssets(cellar.balanceOf(address(cellar))),
            1650e6,
            1, // May be off by 1 due to rounding.
            "Should have minted performance fees to cellar for gains."
        );

        // Simulate losing all previous gains.
        simulateLoss(address(usdcCLR), 500e6); // -$500
        simulateLoss(address(wethCLR), 0.5e18); // -$1000
        simulateLoss(address(wbtcCLR), 0.5e8); // -$15,000

        uint256 performanceFeesBefore = cellar.balanceOf(address(cellar));

        cellar.accrue();

        assertEq(
            cellar.balanceOf(address(cellar)),
            performanceFeesBefore,
            "Should have minted no performance fees for losses."
        );

        // Simulate recovering previous gains.
        simulateGains(address(usdcCLR), 500e6); // $500
        simulateGains(address(wethCLR), 0.5e18); // $1000
        simulateGains(address(wbtcCLR), 0.5e8); // $15,000

        assertEq(
            cellar.balanceOf(address(cellar)),
            performanceFeesBefore,
            "Should have minted no performance fees for no net gains."
        );
    }
}
