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
        address[] memory positions = new address[](5);
        positions[0] = address(USDC);
        positions[1] = address(usdcCLR);
        positions[2] = address(wethCLR);
        positions[3] = address(wbtcCLR);
        positions[4] = address(WETH);

        Cellar.PositionType[] memory positionTypes = new Cellar.PositionType[](5);
        positionTypes[0] = Cellar.PositionType.ERC20;
        positionTypes[1] = Cellar.PositionType.ERC4626;
        positionTypes[2] = Cellar.PositionType.ERC4626;
        positionTypes[3] = Cellar.PositionType.ERC4626;
        positionTypes[4] = Cellar.PositionType.ERC20;

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

    // =========================================== Performance Fee TEST ===========================================
    function testHighWatermark(
        uint256 depositA,
        uint256 depositB,
        uint256 rng
    ) external {
        depositA = bound(depositA, 1000e6, 100000000e6);
        depositB = bound(depositB, 1000e6, 100000000e6);
        rng = bound(rng, 1, type(uint8).max);
        uint256 yield = (depositA + depositB) / rng;

        // Deposit into cellar.
        deal(address(USDC), address(this), (depositA + depositB + 300e6));
        cellar.deposit(depositA, address(this));

        cellar.deposit(depositB, address(this));

        assertEq(1e6, cellar.sharePriceHighWatermark(), "High Watermark should be 1 USDC");

        // Simulate gains.
        uint256 total = depositA + depositB + yield;
        deal(address(USDC), address(cellar), total);

        assertEq(
            cellar.previewMint(100e18),
            cellar.mint(100e18, address(this)),
            "previewMint does not return the same as mint"
        );

        assertEq(
            cellar.previewDeposit(100e6),
            cellar.deposit(100e6, address(this)),
            "previewDeposit does not return the same as deposit"
        );

        cellar.approve(address(cellar), type(uint256).max);
        assertEq(
            cellar.previewWithdraw(depositA / 10),
            cellar.withdraw(depositA / 10, address(this), address(this)),
            "previewWithdraw does not return the same as withdraw"
        );

        assertEq(
            cellar.previewRedeem(100e18),
            cellar.redeem(100e18, address(this), address(this)),
            "previewRedeem does not return the same as redeem"
        );

        uint256 newHWM = (total * 1e6) / (depositA + depositB);
        assertEq(newHWM, cellar.sharePriceHighWatermark(), "High Watermark should be equal to newHWM");
        assertApproxEqRel(
            cellar.previewRedeem(cellar.balanceOf(address(cellar))),
            yield.mulDivDown(cellar.performanceFee(), 1e18),
            0.001e18,
            "Should be within 0.1% of yield * PerformanceFee"
        );
    }

    function testHighWatermarkComplex(uint256 seed) external {
        seed = bound(seed, 1, type(uint72).max);
        deal(address(USDC), address(this), type(uint256).max);
        cellar.approve(address(cellar), type(uint256).max);
        cellar.deposit(1_000_000e6, address(this)); //deposit 1M USDC into Cellar
        uint256 random;
        uint256 amount;
        uint256 HWM;
        uint256 sharePrice;
        uint256 cellarShares;
        uint256 expectedFee;
        uint256 totalSupply;
        for (uint256 i = 0; i < 100; i++) {
            random = uint256(keccak256(abi.encode(seed + i))) % 8; //number between 0 -> 7

            // Force the first 8 iterations to guarantee every scenario is called
            if (i == 0) random = 2; // force withdraw
            if (i == 1) random = 0; // force deposit
            if (i == 2) random = 4; // force gains
            if (i == 3) random = 4; // force gains
            if (i == 4) random = 6; // force loss
            if (i == 5) random = 2; // force withdraw
            if (i == 6) random = 0; // force deposit
            if (i == 7) random = 6; // force loss

            amount = (uint256(keccak256(abi.encode("HOWDY", seed + i))) % 10000e6) + 1000e6; //number between 1000 -> 10,999 USDC
            HWM = cellar.sharePriceHighWatermark();
            cellarShares = cellar.balanceOf(address(cellar));
            sharePrice = (cellar.totalAssets() * 1e18) / cellar.totalSupply();
            totalSupply = cellar.totalSupply();
            if (random < 2) {
                //deposit
                console.log("Deposit", amount, "USDC");
                cellar.deposit(amount, address(this));
            } else if (random < 4) {
                //withdraw
                console.log("Withdraw", amount, "USDC");
                cellar.withdraw(amount, address(this), address(this));
            } else if (random < 6) {
                //yield earned
                console.log("Yield Earned", amount, "USDC");
                deal(address(USDC), address(this), USDC.balanceOf(address(cellar)) + amount);
                uint256 WETHamount = amount.changeDecimals(6, 15);
                console.log("Yield Earned", WETHamount, "WETH");
                deal(address(WETH), address(this), WETH.balanceOf(address(cellar)) + WETHamount);
            } else {
                //yield loss
                console.log("Yield Lossed", amount, "USDC");
                deal(address(USDC), address(this), USDC.balanceOf(address(cellar)) - amount);
                uint256 WETHamount = amount.changeDecimals(6, 15);
                console.log("Yield Lossed", WETHamount, "WETH");
                uint256 newBalance = WETH.balanceOf(address(cellar)) > WETHamount
                    ? WETH.balanceOf(address(cellar)) - WETHamount
                    : 0;
                deal(address(WETH), address(this), newBalance);
            }

            if (random < 4 && sharePrice > HWM) {
                //don't check this if a loss or gain happened cuz no fees would be minted
                assertTrue(cellar.balanceOf(address(cellar)) > cellarShares, "Cellar was not minted Fees");
                expectedFee = ((sharePrice - HWM) * cellar.performanceFee() * totalSupply) / 1e36;
                assertApproxEqRel(
                    expectedFee,
                    cellar.previewRedeem(cellar.balanceOf(address(cellar)) - cellarShares),
                    0.001e18,
                    "Fee Shares minted exceede deviation"
                );
                sharePrice = (cellar.totalAssets() * 1e6) / cellar.totalSupply();
                assertEq(cellar.sharePriceHighWatermark(), sharePrice, "HWM was not set to new Share Price");
            } else {
                // We don't really need to check this if random >= 4, but it can't hurt
                assertTrue(cellar.balanceOf(address(cellar)) == cellarShares, "Cellar was minted Fees");
                assertEq(cellar.sharePriceHighWatermark(), HWM, "HWM was set to new Share Price");
            }
        }
    }
    /*
    function testSendFees() external {
        // Deposit into cellar.
        deal(address(USDC), address(this), 100e6);
        cellar.deposit(100e6, address(this));
        vm.warp(15000000 + 86400);

        cellar.sendFees();
    }

    function sendToCosmos(
        address asset,
        bytes32 feesDistributor,
        uint256 assets
    ) external {}
    */
    // =========================================== ACCRUE TEST ===========================================

    /*function testAccrueWithPositivePerformance() external {
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
    }*/
}
