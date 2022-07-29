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

    address private immutable strategist = vm.addr(0xBEEF);

    address private immutable cosmos = vm.addr(0xCAAA);

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

        cellar.setStrategistPayoutAddress(strategist);
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

    function sendToCosmos(
        address asset,
        bytes32,
        uint256 assets
    ) external {
        ERC20(asset).transferFrom(msg.sender, cosmos, assets);
    }

    // ========================================= DEPOSIT/WITHDRAW TEST =========================================

    function testDepositAndWithdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        deal(address(USDC), address(this), assets);

        (uint256 highWatermarkBeforeDeposit, , , , , , ) = cellar.feeData();

        // Test single deposit.
        uint256 expectedShares = cellar.previewDeposit(assets);
        uint256 shares = cellar.deposit(assets, address(this));

        uint256 expectedHighWatermark = highWatermarkBeforeDeposit + assets;

        (uint256 highWatermarkAfterDeposit, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterDeposit,
            expectedHighWatermark,
            "High watermark should equal high watermark before deposit plus assets deposited by user."
        );

        assertEq(shares, assets.changeDecimals(6, 18), "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(shares, expectedShares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        (uint256 highWatermarkBeforeWithdraw, , , , , , ) = cellar.feeData();

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        expectedHighWatermark = highWatermarkBeforeWithdraw - assets;

        (uint256 highWatermarkAfterWithdraw, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterWithdraw,
            expectedHighWatermark,
            "High watermark should equal high watermark before withdraw minus assets withdrawn by user."
        );

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

    // =========================================== PERFORMANCE/PLATFORM FEE TEST ===========================================

    function testPreviewFunctionsAccountForPerformanceFee(uint256 deposit, uint256 yield) external {
        deposit = bound(deposit, 1_000e6, 100_000_000e6);
        // Cap yield to 100x deposit
        uint256 yieldUpperBound = 100 * deposit;
        // Floor yield above 1e-6x of the deposit
        uint256 yieldLowerBound = deposit / 1_000_000;
        yield = bound(yield, yieldLowerBound, yieldUpperBound);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), type(uint256).max);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        (uint256 currentHWM, , , , , , ) = cellar.feeData();
        assertEq(currentHWM, deposit, "High Watermark should be equal to deposits.");

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), deposit + yield);

        assertEq(
            cellar.previewMint(100e18),
            cellar.mint(100e18, address(this)),
            "`previewMint` should return the same as `mint`."
        );

        assertEq(
            cellar.previewDeposit(100e6),
            cellar.deposit(100e6, address(this)),
            "`previewDeposit` should return the same as `deposit`."
        );

        cellar.approve(address(cellar), type(uint256).max);
        assertEq(
            cellar.previewWithdraw(100e6),
            cellar.withdraw(100e6, address(this), address(this)),
            "`previewWithdraw` should return the same as `withdraw`."
        );

        assertEq(
            cellar.previewRedeem(100e18),
            cellar.redeem(100e18, address(this), address(this)),
            "`previewRedeem` should return the same as `redeem`."
        );
    }

    function testPerformanceFeesWithPositivePerformance(uint256 deposit, uint256 yield) external {
        deposit = bound(deposit, 100e6, 1_000_000e6);
        yield = bound(yield, 10e6, 10_000e6);
        (, , , , uint64 performanceFee, , ) = cellar.feeData();

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), 3 * deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + yield);

        // Deposit into cellar to trigger performance fee calculation.
        cellar.deposit(deposit, address(this));

        uint256 feeSharesInCellar = cellar.balanceOf(address(cellar));
        assertTrue(feeSharesInCellar > 0, "Cellar should have been minted fee shares.");

        uint256 performanceFeeInAssets = cellar.previewRedeem(feeSharesInCellar);
        uint256 expectedPerformanceFeeInAssets = yield.mulWadDown(performanceFee);
        // It is okay for actual performance fee in assets to be equal to or 1 wei less than expected.
        assertTrue(
            performanceFeeInAssets == expectedPerformanceFeeInAssets ||
                performanceFeeInAssets + 1 == expectedPerformanceFeeInAssets,
            "Actual performance fees should equal expected, or actual can be 1 less wei than expected."
        );

        // Deposit into cellar to trigger performance fee calculation.
        cellar.deposit(deposit, address(this));

        assertTrue(
            feeSharesInCellar == cellar.balanceOf(address(cellar)),
            "Cellar should not have been minted more fee shares."
        );
    }

    function testPerformanceFeesWithNegativePerformance(uint256 deposit, uint256 loss) external {
        deposit = bound(deposit, 100_000e6, 1_000_000e6);
        loss = bound(loss, 10e6, 10_000e6);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), 2 * deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Simulate Cellar losing yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) - loss);

        // Deposit into cellar to trigger performance fee calculation.
        cellar.deposit(deposit, address(this));

        assertTrue(cellar.balanceOf(address(cellar)) == 0, "Cellar should not have any fee shares.");
    }

    function testPerformanceFeesWithNeutralPerformance(uint256 deposit, uint256 amount) external {
        deposit = bound(deposit, 100_000e6, 1_000_000e6);
        amount = bound(amount, 10e6, 10_000e6);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), 2 * deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + amount);

        // Simulate Cellar losing yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) - amount);

        // Deposit into cellar to trigger performance fee calculation.
        cellar.deposit(deposit, address(this)); //deposit into Cellar

        assertTrue(cellar.balanceOf(address(cellar)) == 0, "Cellar should not have any fee shares.");
    }

    function testPlatformFees(uint256 timePassed, uint256 deposit) external {
        // Cap timePassed to 1 year. Platform fees will be collected on the order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 1e6, 1_000_000_000e6);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Calculate expected platform fee.
        (, , uint64 strategistPlatformCut, uint64 platformFee, , , ) = cellar.feeData();
        uint256 expectedPlatformFee = (deposit * platformFee * timePassed) / (365 days * 1e18);

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Call `sendFees` to calculate pending platform fees, and distribute them to strategist, and Cosmos.
        cellar.sendFees();

        uint256 feesInAssetsSentToCosmos = USDC.balanceOf(cosmos);
        uint256 feesInAssetsSentToStrategist = cellar.previewRedeem(cellar.balanceOf(strategist));

        assertEq(
            feesInAssetsSentToCosmos,
            expectedPlatformFee.mulWadDown(1e18 - strategistPlatformCut),
            "Platform fee sent to Cosmos should be equal to expectedPlatformFee * (1 - strategistPlatformCut)."
        );

        uint256 expectedPlatformFeeInAssetsSentToStrategist = expectedPlatformFee.mulWadDown(strategistPlatformCut);
        // It is okay for actual fees sent to strategist to be equal to or 1 wei less than expected.
        assertTrue(
            feesInAssetsSentToStrategist == expectedPlatformFeeInAssetsSentToStrategist ||
                feesInAssetsSentToStrategist + 1 == expectedPlatformFeeInAssetsSentToStrategist,
            "Platform fee sent to strategist should be equal to expectedPlatformFee * (strategistPlatformCut)."
        );

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all performance fee shares.");
    }

    function testPlatformAndPerformanceFees(
        uint256 timePassed,
        uint256 deposit,
        uint256 yield
    ) external {
        // Cap timePassed to 1 year. Platform fees will be collected on the order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 1e6, 1_000_000_000e6);
        // Cap yield to 10,000% APR
        uint256 yieldUpperBound = 100 * deposit * (timePassed / 365 days);
        // Floor yield above 0.001% APR
        uint256 yieldLowerBound = (deposit * (timePassed / 365 days)) / 100_000;
        yield = bound(yield, yieldLowerBound, yieldUpperBound);
        (
            ,
            uint64 strategistPerformanceCut,
            uint64 strategistPlatformCut,
            uint64 platformFee,
            uint64 performanceFee,
            ,

        ) = cellar.feeData();

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + yield);

        (uint256 highWatermarkBeforeSendFees, , , , , , ) = cellar.feeData();

        // Call `sendFees` to calculate pending performance and platform fees, and distribute them to strategist, and Cosmos.
        cellar.sendFees();

        uint256 expectedPerformanceFees = yield.mulDivDown(performanceFee, 1e18);

        // Minting platform fees dilutes share price, so it also dilutes pending performance fees.
        uint256 expectedPerformanceFeesAdjustedForDilution = (expectedPerformanceFees *
            (1e18 - (platformFee * timePassed) / 365 days)) / 1e18;

        uint256 expectedPlatformFees = ((deposit + yield) * platformFee * timePassed) / (365 days * 1e18);

        uint256 expectedTotalFeesAdjustedForDilution = expectedPerformanceFeesAdjustedForDilution +
            expectedPlatformFees;

        uint256 feesInAssetsSentToCosmos = USDC.balanceOf(cosmos);
        uint256 feesInAssetsSentToStrategist = cellar.previewRedeem(cellar.balanceOf(strategist));

        assertApproxEqAbs(
            feesInAssetsSentToCosmos + feesInAssetsSentToStrategist,
            expectedTotalFeesAdjustedForDilution,
            1,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected total fees after dilution."
        );

        assertApproxEqAbs(
            feesInAssetsSentToStrategist,
            expectedPlatformFees.mulWadDown(strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(strategistPerformanceCut),
            1,
            "Shares converted to assets sent to strategist should be equal to (total platform fees * strategistPlatformCut) + (total performance fees * strategist performance cut)."
        );

        assertApproxEqAbs(
            feesInAssetsSentToCosmos,
            expectedPlatformFees.mulWadDown(1e18 - strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(1e18 - strategistPerformanceCut),
            1,
            "Assets sent to Cosmos should be equal to (total platform fees * (1-strategistPlatformCut)) + (total performance fees * (1-strategist performance cut))."
        );

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all fee shares.");

        uint256 expectedHighWatermark = highWatermarkBeforeSendFees - feesInAssetsSentToCosmos;

        (uint256 highWatermarkAfterSendFees, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterSendFees,
            expectedHighWatermark,
            "High watermark should equal high watermark before send fees minus assets sent to Cosmos."
        );
    }

    function testResetHighWatermark(
        uint256 deposit,
        uint256 loss,
        uint256 gain
    ) external {
        deposit = bound(deposit, 100_000e6, 1_000_000e6);
        loss = bound(loss, 10e6, 10_000e6);
        gain = bound(gain, 10e6, 10_000e6);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), (2 * deposit) + 1);

        // Deposit into the Cellar.
        cellar.deposit(deposit, address(this)); //deposit into Cellar

        // Simulate Cellar losing yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) - loss);

        // Deposit into the Cellar to check if performance fees are minted.
        cellar.deposit(deposit, address(this));

        assertEq(
            cellar.balanceOf(address(cellar)),
            0,
            "Cellar should have not been minted any performance fee shares."
        );

        // Reset Cellar's High Watermark value.
        cellar.resetHighWatermark();

        (uint256 currentHighWatermark, , , , uint64 performanceFee, , ) = cellar.feeData();
        uint256 expectedHighWatermark = 2 * deposit - loss;
        assertEq(
            currentHighWatermark,
            expectedHighWatermark,
            "Cellar should have reset high watermark to the current assets."
        );

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + gain);

        // Deposit into the Cellar to check that performance fees are minted.
        cellar.deposit(1, address(this));

        assertTrue(cellar.balanceOf(address(cellar)) > 0, "Cellar should have been minted performance fee shares.");

        uint256 expectedPerformanceFeeInAssets = gain.mulWadDown(performanceFee);

        // Cellars rounds down when using previewRedeem, so it is acceptable to be off by 1 wei.
        assertApproxEqAbs(
            cellar.previewRedeem(cellar.balanceOf(address(cellar))),
            expectedPerformanceFeeInAssets,
            1,
            "Cellar performance fee shares in assets should equal (gain * performanceFee)."
        );
    }
}
