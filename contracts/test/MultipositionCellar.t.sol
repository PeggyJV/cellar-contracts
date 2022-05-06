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

        // Initialize with non-zero timestamp to avoid issues with accrual.
        hevm.warp(365 days);
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
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assets);
        assertEq(cellar.balanceOf(address(this)), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets);
        assertEq(USDC.balanceOf(address(this)), 0);

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        assertEq(cellar.totalAssets(), 0);
        assertEq(cellar.balanceOf(address(this)), 0);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0);
        assertEq(USDC.balanceOf(address(this)), assets);
    }

    // TODO: test with fuzzing
    function testRebalance() external {
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

    function testAccrue() external {
        uint256 assets = 100e18;
        uint256 yield = 25e18;

        ERC4626[] memory positions = cellar.getPositions();
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];
            MockERC20 asset = MockERC20(address(position.asset()));

            // Deposit assets directly into position.
            asset.mint(address(this), assets);
            asset.approve(address(cellar), assets);
            cellar.depositIntoPosition(position, assets, address(this));

            assertEq(position.totalAssets(), assets);
            (, , uint112 balance) = cellar.getPositionData(position);
            assertEq(balance, assets);
            assertEq(cellar.totalBalance(), assets * (i + 1));

            // Simulate position accruing yield.
            MockERC4626(address(position)).simulateDeposit(yield, address(cellar));

            assertEq(position.maxWithdraw(address(cellar)), assets + yield);
        }

        uint256 totalAssetsBefore = cellar.totalAssets();
        assertEq(totalAssetsBefore, assets * positions.length);

        uint256 expectedYield = yield * positions.length;
        uint256 expectedPerformanceFeesInAssets = expectedYield.mulDivDown(
            cellar.PERFORMANCE_FEE(),
            cellar.DENOMINATOR()
        );
        uint256 expectedPerformanceFees = cellar.convertToShares(expectedPerformanceFeesInAssets);
        uint256 priceOfShareBefore = cellar.convertToShares(1e18);

        // Test accrue.
        cellar.accrue();

        uint256 priceOfShareAfter = cellar.convertToShares(1e18);
        assertEq(priceOfShareAfter, priceOfShareBefore);
        assertEq(cellar.totalLocked(), expectedYield - expectedPerformanceFeesInAssets);
        assertEq(cellar.totalAssets(), totalAssetsBefore + expectedPerformanceFeesInAssets);
        assertEq(cellar.maxRedeem(address(cellar)), expectedPerformanceFees);
        assertEq(cellar.maxWithdraw(address(cellar)), expectedPerformanceFeesInAssets);

        hevm.warp(block.timestamp + cellar.accrualPeriod());

        assertEq(cellar.totalLocked(), 0);
        assertEq(cellar.totalAssets(), totalAssetsBefore + expectedYield);

        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];

            (, , uint112 balance) = cellar.getPositionData(position);
            assertEq(balance, assets + yield);
        }
    }

    // TODO: address possible error that could happen if not enough to withdraw from all positions
    // due to swap slippage while converting
    function testWithdrawWithoutEnoughHoldings() external {
        uint256 assets = 100e18;

        // Deposit assets directly into position.
        FRAX.mint(address(this), assets);
        FRAX.approve(address(cellar), assets);
        cellar.depositIntoPosition(fraxCLR, assets, address(this));

        FEI.mint(address(this), assets);
        FEI.approve(address(cellar), assets);
        cellar.depositIntoPosition(feiCLR, assets, address(this));

        assertEq(cellar.totalHoldings(), 0);

        // TODO: test withdrawing everything
        uint256 assetsToWithdraw = 10e18;
        cellar.withdraw(assetsToWithdraw, address(this), address(this));

        // TODO: check if totalHoldings percentage approximately equal to the target
        assertEq(USDC.balanceOf(address(this)), assetsToWithdraw);
    }

    function testDistrustingPosition() external {
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
    // function testDepositWithDepositLimits(uint256 assets) external {
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
    // function testDepositWithLiquidityLimits(uint256 assets) external {
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
    // function testDepositWithAllLimits(uint256 assets) external {
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
