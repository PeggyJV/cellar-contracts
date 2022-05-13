// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { MultipositionCellar } from "../templates/MultipositionCellar.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockMultipositionCellar } from "./mocks/MockMultipositionCellar.sol";
import { MockERC4626 } from "./mocks/MockERC4626.sol";
import { MockSwapRouter } from "./mocks/MockSwapRouter.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ISushiSwapRouter } from "../interfaces/ISushiSwapRouter.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { MathUtils } from "../utils/MathUtils.sol";

contract MultipositionCellarTest is DSTestPlus {
    using MathUtils for uint256;

    MockMultipositionCellar private cellar;
    MockSwapRouter private swapRouter;

    MockERC20 private USDC;
    MockERC4626 private usdcCLR;

    MockERC20 private FRAX;
    MockERC4626 private fraxCLR;

    MockERC20 private FEI;
    MockERC4626 private feiCLR;

    function setUp() public {
        // TODO: test USDC with 6 decimals once cellar can handle multiple decimals
        USDC = new MockERC20("USDC", 18);
        usdcCLR = new MockERC4626(ERC20(address(USDC)), "USDC Cellar LP Token", "USDC-CLR", 18);

        FRAX = new MockERC20("FRAX", 18);
        fraxCLR = new MockERC4626(ERC20(address(FRAX)), "FRAX Cellar LP Token", "FRAX-CLR", 18);

        FEI = new MockERC20("FEI", 18);
        feiCLR = new MockERC4626(ERC20(address(FEI)), "FEI Cellar LP Token", "FEI-CLR", 18);

        // Set up stablecoin cellar:
        swapRouter = new MockSwapRouter();

        ERC4626[] memory positions = new ERC4626[](3);
        positions[0] = ERC4626(address(usdcCLR));
        positions[1] = ERC4626(address(fraxCLR));
        positions[2] = ERC4626(address(feiCLR));

        uint256 len = positions.length;

        address[][] memory paths = new address[][](len);
        for (uint256 i; i < len; i++) {
            address[] memory path = new address[](2);
            path[0] = address(positions[i].asset());
            path[1] = address(USDC);

            paths[i] = path;
        }

        uint32[] memory maxSlippages = new uint32[](len);
        for (uint256 i; i < len; i++) maxSlippages[i] = uint32(swapRouter.EXCHANGE_RATE());

        cellar = new MockMultipositionCellar(
            USDC, // TODO: change
            positions,
            paths,
            maxSlippages,
            "Ultimate Stablecoin Cellar LP Token",
            "stble-CLR",
            18,
            ISushiSwapRouter(address(swapRouter))
        );

        // Transfer ownership to this contract for testing.
        hevm.prank(address(cellar.gravityBridge()));
        cellar.transferOwnership(address(this));

        // Mint enough liquidity to swap router for swaps.
        for (uint256 i; i < positions.length; i++) {
            MockERC20 asset = MockERC20(address(positions[i].asset()));
            asset.mint(address(swapRouter), type(uint112).max);
        }
    }

    // TODO: test with fuzzing
    // function testDepositWithdraw(uint256 assets) public {
    function testDepositWithdraw() public {
        // TODO: implement maxDeposit
        // assets = bound(assets, 1, cellar.maxDeposit(address(this)));
        // NOTE: last time this was run, all test pass with the line below uncommented
        // assets = bound(assets, 1, type(uint128).max);
        uint256 assets = 100e18;

        // Test single deposit.
        USDC.mint(address(this), assets);
        USDC.approve(address(cellar), assets);
        uint256 shares = cellar.deposit(assets, address(this));

        assertEq(shares, assets); // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(cellar.previewWithdraw(assets), shares);
        assertEq(cellar.previewDeposit(assets), shares);
        assertEq(cellar.totalBalance(), 0);
        assertEq(cellar.totalHoldings(), assets);
        assertEq(cellar.totalAssets(), assets);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.balanceOf(address(this)), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets);
        assertEq(USDC.balanceOf(address(this)), 0);

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        assertEq(cellar.totalBalance(), 0);
        assertEq(cellar.totalHoldings(), 0);
        assertEq(cellar.totalAssets(), 0);
        assertEq(cellar.totalSupply(), 0);
        assertEq(cellar.balanceOf(address(this)), 0);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0);
        assertEq(USDC.balanceOf(address(this)), assets);
    }

    function testFailDepositWithNotEnoughApproval(uint256 amount) public {
        USDC.mint(address(this), amount / 2);
        USDC.approve(address(cellar), amount / 2);

        cellar.deposit(amount, address(this));
    }

    function testFailWithdrawWithNotEnoughBalance(uint256 amount) public {
        USDC.mint(address(this), amount / 2);
        USDC.approve(address(cellar), amount / 2);

        cellar.deposit(amount / 2, address(this));

        cellar.withdraw(amount, address(this), address(this));
    }

    function testFailRedeemWithNotEnoughBalance(uint256 amount) public {
        USDC.mint(address(this), amount / 2);
        USDC.approve(address(cellar), amount / 2);

        cellar.deposit(amount / 2, address(this));

        cellar.redeem(amount, address(this), address(this));
    }

    function testFailWithdrawWithNoBalance(uint256 amount) public {
        if (amount == 0) amount = 1;
        cellar.withdraw(amount, address(this), address(this));
    }

    function testFailRedeemWithNoBalance(uint256 amount) public {
        cellar.redeem(amount, address(this), address(this));
    }

    function testFailDepositWithNoApproval(uint256 amount) public {
        cellar.deposit(amount, address(this));
    }

    function testFailWithdrawWithSwapOverMaxSlippage() public {
        uint256 assets = 100e18;

        FRAX.mint(address(this), assets);
        FRAX.approve(address(cellar), assets);
        cellar.depositIntoPosition(fraxCLR, assets, address(this));

        assertEq(cellar.totalAssets(), 100e18);

        cellar.setPositionMaxSlippage(fraxCLR, 0);

        cellar.withdraw(50e18, address(this), address(this));
    }

    function testWithdrawWithoutEnoughHoldings() public {
        uint256 assets = 100e18;

        // Deposit assets directly into position.
        FRAX.mint(address(this), assets);
        FRAX.approve(address(cellar), assets);
        cellar.depositIntoPosition(fraxCLR, assets, address(this));

        FEI.mint(address(this), assets);
        FEI.approve(address(cellar), assets);
        cellar.depositIntoPosition(feiCLR, assets, address(this));

        assertEq(cellar.totalHoldings(), 0);
        assertEq(cellar.totalAssets(), 200e18);

        uint256 assetsToWithdraw = 10e18;

        // Test withdraw returns assets to receiver and replenishes holding position.
        cellar.withdraw(assetsToWithdraw, address(this), address(this));

        assertEq(USDC.balanceOf(address(this)), assetsToWithdraw);
        // 10 assets = 5% of 200 total assets (tolerate some assets loss swap slippage)
        assertApproxEq(USDC.balanceOf(address(cellar)), 10e18, 1e18);
    }

    function testWithdrawAllWithHomogenousPositions() public {
        USDC.mint(address(this), 100e18);
        USDC.approve(address(cellar), 100e18);
        cellar.depositIntoPosition(usdcCLR, 100e18, address(this));

        assertEq(cellar.totalAssets(), 100e18);

        cellar.withdraw(100e18, address(this), address(this));

        assertEq(USDC.balanceOf(address(this)), 100e18);
    }

    // NOTE: Although this behavior is not desired, it should be anticipated that this will occur when
    //       withdrawing from a cellar with positions that are not all in the same asset as the holding
    //       position due to the swap slippage involved in needing to convert them all to single asset
    //       received by the user.
    function testFailWithdrawAllWithHeterogenousPositions() public {
        ERC4626[] memory positions = cellar.getPositions();
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];
            MockERC20 asset = MockERC20(address(position.asset()));

            asset.mint(address(this), 100e18);
            asset.approve(address(cellar), 100e18);
            cellar.depositIntoPosition(position, 100e18, address(this));
        }

        assertEq(cellar.totalAssets(), 300e18);

        cellar.withdraw(300e18, address(this), address(this));
    }

    // TODO: test with fuzzing
    function testRebalance() public {
        uint256 assets = 100e18;

        ERC4626[] memory positions = cellar.getPositions();
        ERC4626 positionFrom = positions[0];
        ERC4626 positionTo = positions[1];

        MockERC20 assetFrom = MockERC20(address(positionFrom.asset()));

        assetFrom.mint(address(this), assets);
        assetFrom.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        address[] memory path = new address[](2);

        // Test rebalancing from holding position.
        path[0] = address(assetFrom);
        path[1] = address(assetFrom);

        uint256 assetsRebalanced = cellar.rebalance(cellar, positionFrom, assets, assets, path);

        assertEq(assetsRebalanced, assets);
        assertEq(cellar.totalHoldings(), 0);
        assertEq(positionFrom.balanceOf(address(cellar)), assets);
        (, , uint112 fromBalance) = cellar.getPositionData(positionFrom);
        assertEq(fromBalance, assets);

        // Test rebalancing between positions.
        path[0] = address(assetFrom);
        path[1] = address(positionTo.asset());

        uint256 expectedAssetsOut = swapRouter.quote(assets, path);
        assetsRebalanced = cellar.rebalance(positionFrom, positionTo, assets, expectedAssetsOut, path);

        assertEq(assetsRebalanced, expectedAssetsOut);
        assertEq(positionFrom.balanceOf(address(cellar)), 0);
        assertEq(positionTo.balanceOf(address(cellar)), assetsRebalanced);
        (, , fromBalance) = cellar.getPositionData(positionFrom);
        assertEq(fromBalance, 0);
        (, , uint112 toBalance) = cellar.getPositionData(positionTo);
        assertEq(toBalance, assetsRebalanced);

        // Test rebalancing back to holding position.
        path[0] = address(positionTo.asset());
        path[1] = address(assetFrom);

        expectedAssetsOut = swapRouter.quote(assetsRebalanced, path);
        assetsRebalanced = cellar.rebalance(positionTo, cellar, assetsRebalanced, expectedAssetsOut, path);

        assertEq(assetsRebalanced, expectedAssetsOut);
        assertEq(positionTo.balanceOf(address(cellar)), 0);
        assertEq(cellar.totalHoldings(), assetsRebalanced);
        (, , toBalance) = cellar.getPositionData(positionTo);
        assertEq(toBalance, 0);
    }

    function testFailRebalanceIntoUntrustedPosition() public {
        uint256 assets = 100e18;

        ERC4626[] memory positions = cellar.getPositions();
        ERC4626 untrustedPosition = positions[positions.length - 1];

        cellar.setTrust(untrustedPosition, false);

        MockERC20 asset = MockERC20(address(cellar.asset()));

        asset.mint(address(this), assets);
        asset.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        address[] memory path = new address[](2);

        // Test rebalancing from holding position to untrusted position.
        path[0] = address(asset);
        path[1] = address(untrustedPosition.asset());

        cellar.rebalance(cellar, untrustedPosition, assets, 0, path);
    }

    function testAccrue() public {
        // Scenario:
        //  - Multiposition cellar has 3 positions.
        //  - Current Unix timestamp of test environment is 12345678.
        //
        // Testcases Covered:
        // - Test accrual with positive performance.
        // - Test accrual with negative performance.
        // - Test accrual with no performance (nothing changes).
        // - Test accrual reverting previous accrual period is still ongoing.
        // - Test accrual not starting an accrual period if negative performance or no performance.
        // - Test accrual for single position.
        // - Test accrual for multiple positions.
        // - Test accrued yield is distributed linearly as expected.
        // - Test deposits / withdraws do not effect accrual and yield distribution.
        //
        // +==============+==============+==================+=====================+
        // | Total Assets | Total Locked | Performance Fees |  Last Accrual Time  |
        // |  (in assets) |  (in assets) |    (in shares)   |    (in seconds)     |
        // +==============+==============+==================+=====================+
        // | 1. Deposit 100 assets into each position.                            |
        // +--------------+--------------+------------------+---------------------+
        // |          300 |            0 |                0 |                   0 |
        // +--------------+--------------+------------------+---------------------+
        // | 2. Each position gains 50 assets of yield.                           |
        // |    NOTE: Nothing should change because yield has not been accrued.   |
        // +--------------+--------------+------------------+---------------------+
        // |          300 |            0 |                0 |                   0 |
        // +--------------+--------------+------------------+---------------------+
        // | 3. Accrue with positive performance.                                 |
        // +--------------+--------------+------------------+---------------------+
        // |          315 |          135 |               15 |                   0 |
        // +--------------+--------------+------------------+---------------------+
        // | 4. Half of accrual period passes.                                    |
        // +--------------+--------------+------------------+---------------------+
        // |        382.5 |         67.5 |               15 |            12345678 |
        // +--------------+--------------+------------------+---------------------+
        // | 5. Deposit 200 assets into a position.                               |
        // |    NOTE: For testing that deposit does not effect yield and is not   |
        // |          factored in to later accrual.                               |
        // +--------------+--------------+------------------+---------------------+
        // |        582.5 |         67.5 |               15 |            12345678 |
        // +--------------+--------------+------------------+---------------------+
        // | 6. Entire accrual period passes.                                     |
        // +--------------+--------------+------------------+---------------------+
        // |          650 |            0 |               15 |            12345678 |
        // +--------------+--------------+------------------+---------------------+
        // | 7. Withdraw 100 assets from a position.                              |
        // |    NOTE: For testing that withdraw does not effect yield and is not  |
        // |          factored in to later accrual.                               |
        // +--------------+--------------+------------------+---------------------+
        // |          550 |            0 |               15 |            12345678 |
        // +--------------+--------------+------------------+---------------------+
        // | 8. Accrue with no performance.                                       |
        // |    NOTE: Should not accrue any yield or fees since user deposits     |
        // |          and withdraws are not factored into yield. Also should      |
        // |          not start an accural period since there was no yield        |
        // |          to distribute.                                              |
        // +--------------+--------------+------------------+---------------------+
        // |          550 |            0 |               15 |            12345678 |
        // +--------------+--------------+------------------+---------------------+
        // | 9. A position loses 150 assets of yield.                             |
        // |    NOTE: Nothing should change because losses have not been accrued. |
        // +--------------+--------------+------------------+---------------------+
        // |          550 |            0 |               15 |            12345678 |
        // +--------------+--------------+------------------+---------------------+
        // | 10. Accrue with negative performance.                                |
        // |    NOTE: Should not start an accrual period since losses are         |
        // |          realized immediately.                                       |
        // +--------------+--------------+------------------+---------------------+
        // |          400 |            0 |               15 |            12345678 |
        // +--------------+--------------+------------------+---------------------+

        // Initialize timestamp of test environment to 12345678.
        hevm.warp(12345678);

        ERC4626[] memory positions = cellar.getPositions();
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];
            MockERC20 asset = MockERC20(address(position.asset()));

            // 1. Deposit 100 assets into each position.
            asset.mint(address(this), 100e18);
            asset.approve(address(cellar), 100e18);
            cellar.depositIntoPosition(position, 100e18, address(this));

            assertEq(position.totalAssets(), 100e18);
            (, , uint112 balance) = cellar.getPositionData(position);
            assertEq(balance, 100e18);
            assertEq(cellar.totalBalance(), 100e18 * (i + 1));

            // 2. Each position gains 50 assets of yield.
            MockERC4626(address(position)).simulateGain(50e18, address(cellar));

            assertEq(position.maxWithdraw(address(cellar)), 150e18);
        }

        assertEq(cellar.totalAssets(), 300e18);

        uint256 priceOfShareBefore = cellar.convertToShares(1e18);

        // 3. Accrue with positive performance.
        cellar.accrue();

        uint256 priceOfShareAfter = cellar.convertToShares(1e18);
        assertEq(priceOfShareAfter, priceOfShareBefore);
        assertEq(cellar.totalLocked(), 135e18);
        assertEq(cellar.totalAssets(), 315e18);
        assertEq(cellar.totalBalance(), 450e18);
        assertEq(cellar.accruedPerformanceFees(), 15e18);
        assertEq(cellar.lastAccrual(), 12345678);

        // Position balances should have updated to reflect yield accrued per position.
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];

            (, , uint112 balance) = cellar.getPositionData(position);
            assertEq(balance, 150e18);
        }

        // 4. Half of accrual period passes.
        uint256 accrualPeriod = cellar.accrualPeriod();
        hevm.warp(block.timestamp + accrualPeriod / 2);

        assertEq(cellar.totalLocked(), 67.5e18);
        assertApproxEq(cellar.totalAssets(), 382.5e18, 1e17);
        assertApproxEq(cellar.totalBalance(), 450e18, 1e17);
        assertEq(cellar.accruedPerformanceFees(), 15e18);
        assertEq(cellar.lastAccrual(), 12345678);

        // 5. Deposit 200 assets into a position.
        USDC.mint(address(this), 200e18);
        USDC.approve(address(cellar), 200e18);
        cellar.depositIntoPosition(usdcCLR, 200e18, address(this));

        assertEq(cellar.totalLocked(), 67.5e18);
        assertApproxEq(cellar.totalAssets(), 582.5e18, 1e17);
        assertApproxEq(cellar.totalBalance(), 650e18, 1e17);
        assertEq(cellar.accruedPerformanceFees(), 15e18);
        assertEq(cellar.lastAccrual(), 12345678);

        // 6. Entire accrual period passes.
        hevm.warp(block.timestamp + accrualPeriod / 2);

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 650e18, 1e17);
        assertApproxEq(cellar.totalBalance(), 650e18, 1e17);
        assertEq(cellar.accruedPerformanceFees(), 15e18);
        assertEq(cellar.lastAccrual(), 12345678);

        // 7. Withdraw 100 assets from a position.
        cellar.withdrawFromPosition(fraxCLR, 100e18, address(this), address(this));

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 550e18, 1e17);
        assertApproxEq(cellar.totalBalance(), 550e18, 1e17);
        assertEq(cellar.accruedPerformanceFees(), 15e18);
        assertEq(cellar.lastAccrual(), 12345678);

        // 8. Accrue with no performance.
        cellar.accrue();

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 550e18, 1e17);
        assertApproxEq(cellar.totalBalance(), 550e18, 1e17);
        assertEq(cellar.accruedPerformanceFees(), 15e18);
        assertEq(cellar.lastAccrual(), 12345678);

        // 9. A position loses 150 assets of yield.
        MockERC4626(address(feiCLR)).simulateLoss(150e18);

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 550e18, 1e17);
        assertApproxEq(cellar.totalBalance(), 550e18, 1e17);
        assertEq(cellar.accruedPerformanceFees(), 15e18);
        assertEq(cellar.lastAccrual(), 12345678);

        // 10. Accrue with negative performance.
        cellar.accrue();

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 400e18, 1e17);
        assertApproxEq(cellar.totalBalance(), 400e18, 1e17);
        assertEq(cellar.accruedPerformanceFees(), 15e18);
        assertEq(cellar.lastAccrual(), 12345678);
    }

    function testDistrustingPosition() public {
        ERC4626 distrustedPosition = fraxCLR;

        cellar.setTrust(distrustedPosition, false);

        (bool isTrusted, , ) = cellar.getPositionData(distrustedPosition);
        assertFalse(isTrusted);

        ERC4626[] memory positions = cellar.getPositions();
        for (uint256 i; i < positions.length; i++) assertTrue(positions[i] != distrustedPosition);
    }

    // // TODO:
    // // [ ] test hitting depositLimit
    // // [ ] test hitting liquidityLimit

    // // Test deposit hitting liquidity limit.
    // function testDepositWithDepositLimits(uint256 assets) public {
    //     assets = bound(assets, 1, type(uint128).max);

    //     uint248 depositLimit = 50_000e18;
    //     usdcCLR.setDepositLimit(depositLimit);

    //     uint256 expectedAssets = MathUtils.min(depositLimit, assets);

    //     // Test with holdings limit.
    //     USDC.mint(address(this), assets);
    //     USDC.approve(address(cellar), assets);
    //     uint256 shares = cellar.deposit(assets, address(this));

    //     assertEq(cellar.totalAssets(), expectedAssets);
    //     assertEq(cellar.previewDeposit(expectedAssets), shares);
    // }

    // // Test deposit hitting deposit limit.
    // function testDepositWithLiquidityLimits(uint256 assets) public {
    //     assets = bound(assets, 1, type(uint128).max);

    //     uint248 liquidityLimit = 75_000e18;
    //     usdcCLR.setLiquidityLimit(liquidityLimit);

    //     uint256 expectedAssets = MathUtils.min(liquidityLimit, assets);

    //     // Test with liquidity limit.
    //     USDC.mint(address(this), assets);
    //     USDC.approve(address(cellar), assets);
    //     uint256 shares = cellar.deposit(assets, address(this));

    //     assertEq(cellar.totalAssets(), expectedAssets);
    //     assertEq(cellar.previewDeposit(expectedAssets), shares);
    // }

    // // Test deposit hitting both limits.
    // function testDepositWithAllLimits(uint256 assets) public {
    //     assets = bound(assets, 1, type(uint128).max);

    //     uint248 holdingsLimit = 25_000e18;
    //     cellar.setHoldingLimit(ERC4626(address(usdcCLR)), holdingsLimit);

    //     uint248 depositLimit = 50_000e18;
    //     usdcCLR.setDepositLimit(depositLimit);

    //     uint248 liquidityLimit = 75_000e18;
    //     usdcCLR.setLiquidityLimit(liquidityLimit);

    //     uint256 expectedAssets = MathUtils.min(holdingsLimit, assets);

    //     // Test with liquidity limit.
    //     USDC.mint(address(this), assets);
    //     USDC.approve(address(cellar), assets);
    //     uint256 shares = cellar.deposit(assets, address(this));

    //     assertEq(cellar.totalAssets(), expectedAssets);
    //     assertEq(cellar.previewDeposit(expectedAssets), shares);
    // }
}
