// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { MultipositionCellar } from "../templates/MultipositionCellar.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockWETH } from "./mocks/MockWETH.sol";
import { MockMultipositionCellar } from "./mocks/MockMultipositionCellar.sol";
import { MockERC4626 } from "./mocks/MockERC4626.sol";
import { MockSwapRouter } from "./mocks/MockSwapRouter.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { MathUtils } from "../utils/MathUtils.sol";

// TODO: test with fuzzing

contract MultipositionCellarTest is DSTestPlus {
    using MathUtils for uint256;

    MockMultipositionCellar private cellar;
    MockMultipositionCellar private cellar2;
    MockSwapRouter private swapRouter;

    MockERC20 private USDC;
    MockERC4626 private usdcCLR;

    MockWETH private WETH;
    MockERC4626 private wethCLR;
    MockERC4626 private ethCLR;

    MockERC20 private WBTC;
    MockERC4626 private wbtcCLR;

    function setUp() public {
        swapRouter = new MockSwapRouter();
        hevm.label(address(swapRouter), "swapRouter");

        WETH = new MockWETH();
        hevm.label(address(WETH), "WETH");
        wethCLR = new MockERC4626(ERC20(address(WETH)), "WETH Cellar LP Token", "WETH-CLR", 18, false, address(WETH));
        hevm.label(address(wethCLR), "wethCLR");

        ethCLR = new MockERC4626(ERC20(address(WETH)), "ETH Cellar LP Token", "ETH-CLR", 18, true, address(WETH));
        hevm.label(address(ethCLR), "ethCLR");

        USDC = new MockERC20("USDC", 6);
        hevm.label(address(USDC), "USDC");
        usdcCLR = new MockERC4626(ERC20(address(USDC)), "USDC Cellar LP Token", "USDC-CLR", 6, false, address(WETH));
        hevm.label(address(usdcCLR), "usdcCLR");

        WBTC = new MockERC20("WBTC", 8);
        hevm.label(address(WBTC), "WBTC");
        wbtcCLR = new MockERC4626(ERC20(address(WBTC)), "WBTC Cellar LP Token", "WBTC-CLR", 8, false, address(WETH));
        hevm.label(address(wbtcCLR), "wbtcCLR");

        // Setup exchange rates:
        swapRouter.setExchangeRate(address(USDC), address(USDC), 1e6);
        swapRouter.setExchangeRate(address(WETH), address(WETH), 1e18);
        swapRouter.setExchangeRate(address(WBTC), address(WBTC), 1e8);

        swapRouter.setExchangeRate(address(USDC), address(WETH), 0.0005e18);
        swapRouter.setExchangeRate(address(WETH), address(USDC), 2000e6);

        swapRouter.setExchangeRate(address(USDC), address(WBTC), 0.000033e8);
        swapRouter.setExchangeRate(address(WBTC), address(USDC), 30_000e6);

        swapRouter.setExchangeRate(address(WETH), address(WBTC), 0.06666666e8);
        swapRouter.setExchangeRate(address(WBTC), address(WETH), 15e18);

        // Setup cellar:
        ERC4626[] memory positions = new ERC4626[](3);
        positions[0] = ERC4626(payable(address(usdcCLR)));
        positions[1] = ERC4626(payable(address(wethCLR)));
        positions[2] = ERC4626(payable(address(wbtcCLR)));

        uint256 len = positions.length;

        address[][] memory paths = new address[][](len);
        for (uint256 i; i < len; i++) {
            address[] memory path = new address[](2);
            path[0] = address(positions[i].asset());
            path[1] = address(USDC);

            paths[i] = path;
        }

        uint32[] memory maxSlippages = new uint32[](len);
        for (uint256 i; i < len; i++) maxSlippages[i] = uint32(swapRouter.PRICE_IMPACT());

        cellar = new MockMultipositionCellar(
            USDC,
            positions,
            paths,
            maxSlippages,
            ISwapRouter(address(swapRouter)),
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            6,
            address(WETH)
        );
        
        hevm.label(address(cellar), "cellar");

        // Transfer ownership to this contract for testing.
        hevm.prank(address(cellar.gravityBridge()));
        cellar.transferOwnership(address(this));

        // Mint enough liquidity to swap router for swaps.
        for (uint256 i; i < positions.length; i++) {
            MockERC20 asset = MockERC20(address(positions[i].asset()));
            asset.mint(address(swapRouter), type(uint112).max);
        }

        // Setup cellar2:
        ERC4626[] memory positions2 = new ERC4626[](3);
        positions2[0] = ERC4626(payable(address(cellar)));
        positions2[1] = ERC4626(payable(address(wethCLR)));
        positions2[2] = ERC4626(payable(address(ethCLR)));        

        uint256 len2 = positions2.length;

        address[][] memory paths2 = new address[][](len2);
        for (uint256 i; i < len2; i++) {
            address[] memory path2 = new address[](2);
            path2[0] = address(positions2[i].asset());
            path2[1] = address(WETH);

            paths2[i] = path2;
        }

        uint32[] memory maxSlippages2 = new uint32[](len2);
        for (uint256 i; i < len2; i++) maxSlippages2[i] = uint32(swapRouter.PRICE_IMPACT());

        cellar2 = new MockMultipositionCellar(
            MockERC20(address(WETH)),
            positions2,
            paths2,
            maxSlippages2,
            ISwapRouter(address(swapRouter)),
            "Multiposition Cellar2 LP Token",
            "multiposition-CLR2",
            18,
            address(WETH)
        );

        hevm.label(address(cellar2), "cellar2");

        // Transfer ownership to this contract for testing.
        hevm.prank(address(cellar2.gravityBridge()));
        cellar2.transferOwnership(address(this));

        // Mint enough liquidity to swap router for swaps.
        for (uint256 i; i < positions2.length; i++) {
            MockERC20 asset = MockERC20(address(positions2[i].asset()));
            asset.mint(address(swapRouter), type(uint112).max);
        }
    }

    // ========================================= DEPOSIT/WITHDRAW TEST =========================================

    function testDepositWithdraw() public {
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
    
    function testDepositWithdrawETH() public {
        uint256 assets = 100e18;

        uint256 balanceBefore = address(this).balance;
        emit log_named_uint("balanceBefore: ", balanceBefore);

        // Test single deposit native ETH
        uint256 shares = cellar2.depositETH{value: assets}(address(this));

        assertEq(shares, assets); // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(cellar2.previewWithdraw(assets), shares);
        assertEq(cellar2.previewDeposit(assets), shares);
        assertEq(cellar2.totalBalance(), 0);
        assertEq(cellar2.totalHoldings(), assets);
        assertEq(cellar2.totalAssets(), assets);
        assertEq(cellar2.totalSupply(), shares);
        assertEq(cellar2.balanceOf(address(this)), shares);
        assertEq(cellar2.convertToAssets(cellar2.balanceOf(address(this))), assets);
        assertEq(address(this).balance, balanceBefore - assets);
        assertEq(address(WETH).balance, assets);

        // Test single withdraw.
        cellar2.withdrawETH(assets, address(this), address(this));

        assertEq(cellar2.totalBalance(), 0);
        assertEq(cellar2.totalHoldings(), 0);
        assertEq(cellar2.totalAssets(), 0);
        assertEq(cellar2.totalSupply(), 0);
        assertEq(cellar2.balanceOf(address(this)), 0);
        assertEq(cellar2.convertToAssets(cellar2.balanceOf(address(this))), 0);
        assertEq(address(this).balance, balanceBefore);
        assertEq(address(WETH).balance, 0);
    }

    function testFailDepositWithNotEnoughApproval(uint256 assets) public {
        USDC.mint(address(this), assets / 2);
        USDC.approve(address(cellar), assets / 2);

        cellar.deposit(assets, address(this));
    }

    function testFailWithdrawWithNotEnoughBalance(uint256 assets) public {
        USDC.mint(address(this), assets / 2);
        USDC.approve(address(cellar), assets / 2);

        cellar.deposit(assets / 2, address(this));

        cellar.withdraw(assets, address(this), address(this));
    }

    function testFailRedeemWithNotEnoughBalance(uint256 assets) public {
        USDC.mint(address(this), assets / 2);
        USDC.approve(address(cellar), assets / 2);

        cellar.deposit(assets / 2, address(this));

        cellar.redeem(assets, address(this), address(this));
    }

    function testFailWithdrawWithNoBalance(uint256 assets) public {
        if (assets == 0) assets = 1;
        cellar.withdraw(assets, address(this), address(this));
    }

    function testFailRedeemWithNoBalance(uint256 assets) public {
        cellar.redeem(assets, address(this), address(this));
    }

    function testFailDepositWithNoApproval(uint256 assets) public {
        cellar.deposit(assets, address(this));
    }

    function testFailWithdrawWithSwapOverMaxSlippage() public {
        WETH.deposit{value: 1e18}();
        WETH.approve(address(cellar), 1e18);
        cellar.depositIntoPosition(wethCLR, 1e18, address(this));

        assertEq(cellar.totalAssets(), 2000e6);

        cellar.setMaxSlippage(wethCLR, 0);

        cellar.withdraw(1e6, address(this), address(this));
    }

    function testWithdrawWithoutEnoughHoldings() public {
        // Deposit assets directly into position.
        WETH.deposit{value: 1e18}();
        WETH.approve(address(cellar), 1e18);
        cellar.depositIntoPosition(wethCLR, 1e18, address(this)); // $2000

        WBTC.mint(address(this), 1e8);
        WBTC.approve(address(cellar), 1e8);
        cellar.depositIntoPosition(wbtcCLR, 1e8, address(this)); // $30,000

        assertEq(cellar.totalHoldings(), 0);
        assertEq(cellar.totalAssets(), 32_000e6);

        // Test withdraw returns assets to receiver and replenishes holding position.
        cellar.withdraw(10e6, address(this), address(this));

        assertEq(USDC.balanceOf(address(this)), 10e6);
        // $1,600 = 5% of $32,000 (tolerate some assets loss due to swap slippage).
        assertApproxEq(USDC.balanceOf(address(cellar)), 1600e6, 100e6);
    }

    function testWithdrawETHWithoutEnoughHoldings() public {
        // Deposit assets directly into position.
        WETH.deposit{value: 10e18}();
        WETH.approve(address(cellar2), 3e18);

        USDC.mint(address(this), 1e8);
        USDC.approve(address(cellar2), 1e8);

        cellar2.depositIntoPosition(cellar, 1e8, address(this)); // 0.05 ether
        cellar2.depositIntoPosition(wethCLR, 1e18, address(this)); // 1 ether
        cellar2.depositIntoPosition(ethCLR, 1e18, address(this)); // 1 ether

        assertEq(cellar2.totalHoldings(), 0);
        assertEq(cellar2.totalAssets(), 205e16);

        // Test withdraw returns assets to receiver and replenishes holding position.
        cellar2.withdrawETH(2e18, address(this), address(this));

        assertEq(WETH.balanceOf(address(this)), 8e18); // 10e18 - 2e18 = 8e18
//         // 0.0475 ether = 5% of 0.95 ether (tolerate some assets loss due to swap slippage).
        assertApproxEq(WETH.balanceOf(address(cellar2)), 475e14, 10e14);
    }
/*
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
        USDC.mint(address(this), 100e6);
        USDC.approve(address(cellar), 100e6);
        cellar.depositIntoPosition(usdcCLR, 100e6, address(this)); // $100

        WETH.deposit{value: 1e18}();
        WETH.approve(address(cellar), 1e18);
        cellar.depositIntoPosition(wethCLR, 1e18, address(this)); // $2,000

        WBTC.mint(address(this), 1e8);
        WBTC.approve(address(cellar), 1e8);
        cellar.depositIntoPosition(wbtcCLR, 1e8, address(this)); // $30,000

        assertEq(cellar.totalAssets(), 32_100e6);

        cellar.withdraw(32_100e6, address(this), address(this));
    }

    // =========================================== REBALANCE TEST ===========================================

    function testRebalance() public {
        USDC.mint(address(this), 10_000e6);
        USDC.approve(address(cellar), 10_000e6);
        cellar.deposit(10_000e6, address(this));

        address[] memory path = new address[](2);

        // Test rebalancing from holding position.
        path[0] = address(USDC);
        path[1] = address(USDC);

        uint256 assetsRebalanced = cellar.rebalance(cellar, usdcCLR, 10_000e6, 10_000e6, path);

        assertEq(assetsRebalanced, 10_000e6);
        assertEq(cellar.totalHoldings(), 0);
        assertEq(usdcCLR.balanceOf(address(cellar)), 10_000e6);
        (, , uint112 fromBalance) = cellar.getPositionData(usdcCLR);
        assertEq(fromBalance, 10_000e6);

        // Test rebalancing between positions.
        path[0] = address(USDC);
        path[1] = address(WETH);

        uint256 expectedAssetsOut = swapRouter.quote(10_000e6, path);
        assetsRebalanced = cellar.rebalance(usdcCLR, wethCLR, 10_000e6, expectedAssetsOut, path);

        assertEq(assetsRebalanced, expectedAssetsOut);
        assertEq(usdcCLR.balanceOf(address(cellar)), 0);
        assertEq(wethCLR.balanceOf(address(cellar)), assetsRebalanced);
        (, , fromBalance) = cellar.getPositionData(usdcCLR);
        assertEq(fromBalance, 0);
        (, , uint112 toBalance) = cellar.getPositionData(wethCLR);
        assertEq(toBalance, assetsRebalanced);

        // Test rebalancing back to holding position.
        path[0] = address(WETH);
        path[1] = address(USDC);

        expectedAssetsOut = swapRouter.quote(assetsRebalanced, path);
        assetsRebalanced = cellar.rebalance(wethCLR, cellar, assetsRebalanced, expectedAssetsOut, path);

        assertEq(assetsRebalanced, expectedAssetsOut);
        assertEq(wethCLR.balanceOf(address(cellar)), 0);
        assertEq(cellar.totalHoldings(), assetsRebalanced);
        (, , toBalance) = cellar.getPositionData(wethCLR);
        assertEq(toBalance, 0);
    }

    function testFailRebalanceFromPositionWithNotEnoughBalance() public {
        uint256 assets = 100e18;

        USDC.mint(address(this), assets / 2);
        USDC.approve(address(cellar), assets / 2);

        cellar.depositIntoPosition(usdcCLR, assets / 2, address(this));

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WBTC);

        uint256 expectedAssetsOut = swapRouter.quote(assets, path);
        cellar.rebalance(usdcCLR, wbtcCLR, assets, expectedAssetsOut, path);
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

    // ============================================= ACCRUE TEST =============================================

    function testAccrue() public {
        // Scenario:
        //  - Multiposition cellar has 3 positions.
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

        // NOTE: The amounts in each column are approximations. Actual results may differ due
        //       to swaps and decimal conversions, however, it should not be significant.
        // +==============+==============+==================+================+===================+==============+
        // | Total Assets | Total Locked | Performance Fees | Platform Fees  | Last Accrual Time | Current Time |
        // |   (in USD)   |   (in USD)   |    (in shares)   |  (in shares)   |   (in seconds)    | (in seconds) |
        // +==============+==============+==================+================+===================+==============+
        // | 1. Deposit $100 worth of assets into each position.                                                |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $300 |           $0 |                0 |              0 |                 0 |            0 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 2. An entire year passes.                                                                          |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $300 |           $0 |                0 |              0 |                 0 |     31536000 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 3. Test accrual of platform fees.                                                                  |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $300 |           $0 |                0 |              3 |          31536000 |     31536000 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 4. Each position gains $50 worth of assets of yield.                                               |
        // |    NOTE: Nothing should change because yield has not been accrued.                                 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $300 |           $0 |                0 |              3 |          31536000 |     31536000 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 5. Accrue with positive performance.                                                               |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $315 |         $135 |               15 |              3 |          31536000 |     31536000 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 6. Half of accrual period passes.                                                                  |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |       $382.5 |        $67.5 |               15 |              3 |          31536000 |     31838400 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 7. Deposit $200 worth of assets into a position.                                                   |
        // |    NOTE: For testing that deposit does not effect yield and is not factored in to later accrual.   |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |       $582.5 |        $67.5 |               15 |              3 |          31536000 |     31838400 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 8. Entire accrual period passes.                                                                   |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $650 |           $0 |               15 |              3 |          31536000 |     32140800 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 9. Withdraw $100 worth of assets from a position.                                                  |
        // |    NOTE: For testing that withdraw does not effect yield and is not factored in to later accrual.  |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $550 |           $0 |               15 |              3 |          31536000 |     32140800 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 10. Accrue with no performance.                                                                    |
        // |    NOTE: Ignore platform fees from now on because we've already tested they work and amounts at    |
        // |          this timescale are very small.                                                            |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $550 |           $0 |               15 |              3 |          32140800 |     32140800 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 11. A position loses $150 worth of assets of yield.                                                |
        // |    NOTE: Nothing should change because losses have not been accrued.                               |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $550 |           $0 |               15 |              3 |          32140800 |     32140800 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 12. Accrue with negative performance.                                                              |
        // |    NOTE: Losses are realized immediately.                                                          |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $400 |           $0 |               15 |              3 |          32745600 |     32745600 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+

        ERC4626[] memory positions = cellar.getPositions();

        // 1. Deposit $100 worth of assets into each position.
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];
            MockERC20 positionAsset = MockERC20(address(position.asset()));

            uint256 assets = swapRouter.convert(address(USDC), address(positionAsset), 100e6);
            positionAsset.mint(address(this), assets);
            positionAsset.approve(address(cellar), assets);
            cellar.depositIntoPosition(position, assets, address(this));

            assertEq(position.totalAssets(), assets);
            (, , uint112 balance) = cellar.getPositionData(position);
            assertEq(balance, assets);
            assertApproxEq(cellar.totalBalance(), 100e6 * (i + 1), 1e6);
        }

        assertApproxEq(cellar.totalAssets(), 300e6, 1e6);

        // 2. An entire year passes.
        hevm.warp(block.timestamp + 365 days);
        uint256 lastAccrualTimestamp = block.timestamp;

        // 3. Accrue platform fees.
        cellar.accrue();

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 300e6, 1e6);
        assertApproxEq(cellar.totalBalance(), 300e6, 1e6);
        assertApproxEq(cellar.balanceOf(address(cellar)), 3e6, 0.01e6);
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp);

        // 4. Each position gains $50 worth of assets of yield.
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];
            MockERC20 positionAsset = MockERC20(address(position.asset()));

            uint256 assets = swapRouter.convert(address(USDC), address(positionAsset), 50e6);
            MockERC4626(payable(address(position))).simulateGain(assets, address(cellar));
            assertApproxEq(cellar.convertToAssets(positionAsset, position.maxWithdraw(address(cellar))), 150e6, 2e6);
        }

        uint256 priceOfShareBefore = cellar.convertToShares(1e6);

        // 5. Accrue with positive performance.
        cellar.accrue();

        uint256 priceOfShareAfter = cellar.convertToShares(1e6);
        assertEq(priceOfShareAfter, priceOfShareBefore);
        assertApproxEq(cellar.totalLocked(), 135e6, 1e6);
        assertApproxEq(cellar.totalAssets(), 315e6, 2e6);
        assertApproxEq(cellar.totalBalance(), 450e6, 2e6);
        assertApproxEq(cellar.balanceOf(address(cellar)), 18e6, 1e6);
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp);

        // Position balances should have updated to reflect yield accrued per position.
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];

            (, , uint112 balance) = cellar.getPositionData(position);
            assertApproxEq(cellar.convertToAssets(position.asset(), balance), 150e6, 2e6);
        }

        // 6. Half of accrual period passes.
        uint256 accrualPeriod = cellar.accrualPeriod();
        hevm.warp(block.timestamp + accrualPeriod / 2);

        assertApproxEq(cellar.totalLocked(), 67.5e6, 1e6);
        assertApproxEq(cellar.totalAssets(), 382.5e6, 2e6);
        assertApproxEq(cellar.totalBalance(), 450e6, 2e6);
        assertApproxEq(cellar.balanceOf(address(cellar)), 18e6, 1e6);
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp);

        // 7. Deposit $200 worth of assets into a position.
        USDC.mint(address(this), 200e6);
        USDC.approve(address(cellar), 200e6);
        cellar.depositIntoPosition(usdcCLR, 200e6, address(this));

        assertApproxEq(cellar.totalLocked(), 67.5e6, 1e6);
        assertApproxEq(cellar.totalAssets(), 582.5e6, 2e6);
        assertApproxEq(cellar.totalBalance(), 650e6, 2e6);
        assertApproxEq(cellar.balanceOf(address(cellar)), 18e6, 1e6);
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp);

        // 8. Entire accrual period passes.
        hevm.warp(block.timestamp + accrualPeriod / 2);

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 650e6, 2e6);
        assertApproxEq(cellar.totalBalance(), 650e6, 2e6);
        assertApproxEq(cellar.balanceOf(address(cellar)), 18e6, 1e6);
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp);

        // 9. Withdraw $100 worth of assets from a position.
        cellar.withdrawFromPosition(
            wethCLR,
            swapRouter.convert(address(USDC), address(WETH), 100e6),
            address(this),
            address(this)
        );

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 550e6, 2e6);
        assertApproxEq(cellar.totalBalance(), 550e6, 2e6);
        assertApproxEq(cellar.balanceOf(address(cellar)), 18e6, 1e6);
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp);

        // 10. Accrue with no performance.
        cellar.accrue();
        lastAccrualTimestamp = block.timestamp;

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 550e6, 2e6);
        assertApproxEq(cellar.totalBalance(), 550e6, 2e6);
        assertApproxEq(cellar.balanceOf(address(cellar)), 18e6, 1e6);
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp);

        // 11. A position loses $150 worth of assets of yield.
        MockERC4626(payable(address(usdcCLR))).simulateLoss(150e6);

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 550e6, 2e6);
        assertApproxEq(cellar.totalBalance(), 550e6, 2e6);
        assertApproxEq(cellar.balanceOf(address(cellar)), 18e6, 1e6);
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp);

        // 12. Accrue with negative performance.
        cellar.accrue();

        assertEq(cellar.totalLocked(), 0);
        assertApproxEq(cellar.totalAssets(), 400e6, 2e6);
        assertApproxEq(cellar.totalBalance(), 400e6, 2e6);
        assertApproxEq(cellar.balanceOf(address(cellar)), 18e6, 1e6);
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp);
    }

    function testAccrueWithZeroTotalLocked() public {
        cellar.accrue();

        assertEq(cellar.totalLocked(), 0);

        cellar.accrue();
    }

    function testFailAccrueWithNonzeroTotalLocked() public {
        MockERC4626(payable(address(usdcCLR))).simulateGain(100e6, address(cellar));
        cellar.accrue();

        // $90 locked after taking $10 for 10% performance fees.
        assertEq(cellar.totalLocked(), 90e6);

        cellar.accrue();
    }

    // ============================================= POSITIONS TEST =============================================

    function testSetPositions() public {
        ERC4626[] memory positions = new ERC4626[](3);
        positions[0] = ERC4626(payable(address(wethCLR)));
        positions[1] = ERC4626(payable(address(usdcCLR)));
        positions[2] = ERC4626(payable(address(wbtcCLR)));

        uint32[] memory maxSlippages = new uint32[](3);
        for (uint256 i; i < 3; i++) maxSlippages[i] = 1_00;

        cellar.setPositions(positions, maxSlippages);

        // Test that positions were updated.
        ERC4626[] memory newPositions = cellar.getPositions();
        uint32 maxSlippage;
        for (uint256 i; i < 3; i++) {
            ERC4626 position = positions[i];

            assertEq(address(position), address(newPositions[i]));
            (, maxSlippage, ) = cellar.getPositionData(position);
            assertEq(maxSlippage, 1_00);
        }
    }

    function testFailSetUntrustedPosition() public {
        MockERC20 XYZ = new MockERC20("XYZ", 18);
        MockERC4626 xyzCLR = new MockERC4626(ERC20(address(XYZ)), "XYZ Cellar LP Token", "XYZ-CLR", 18, false, address(WETH));

        (bool isTrusted, , ) = cellar.getPositionData(xyzCLR);
        assertFalse(isTrusted);

        ERC4626[] memory positions = new ERC4626[](4);
        positions[0] = ERC4626(payable(address(wethCLR)));
        positions[1] = ERC4626(payable(address(usdcCLR)));
        positions[2] = ERC4626(payable(address(wbtcCLR)));
        positions[3] = ERC4626(payable(address(xyzCLR)));

        // Test attempting to setting with an untrusted position.
        cellar.setPositions(positions);
    }

    function testFailAddingUntrustedPosition() public {
        MockERC20 XYZ = new MockERC20("XYZ", 18);
        MockERC4626 xyzCLR = new MockERC4626(ERC20(address(XYZ)), "XYZ Cellar LP Token", "XYZ-CLR", 18, false, address(WETH));

        (bool isTrusted, , ) = cellar.getPositionData(xyzCLR);
        assertFalse(isTrusted);

        // Test attempting to add untrusted position.
        cellar.addPosition(xyzCLR);
    }

    function testTrustingPosition() public {
        MockERC20 XYZ = new MockERC20("XYZ", 18);
        MockERC4626 xyzCLR = new MockERC4626(ERC20(address(XYZ)), "XYZ Cellar LP Token", "XYZ-CLR", 18, false, address(WETH));

        (bool isTrusted, , ) = cellar.getPositionData(xyzCLR);
        assertFalse(isTrusted);

        // Test that position is trusted.
        cellar.setTrust(xyzCLR, true);

        (isTrusted, , ) = cellar.getPositionData(xyzCLR);
        assertTrue(isTrusted);

        // Test that newly trusted position can now be added.
        cellar.addPosition(xyzCLR);

        ERC4626[] memory positions = cellar.getPositions();
        assertEq(address(positions[positions.length - 1]), address(xyzCLR));
    }

    function testDistrustingAndRemovingPosition() public {
        ERC4626 distrustedPosition = wethCLR;

        // Deposit assets into position before distrusting.
        uint256 assets = swapRouter.convert(address(USDC), address(WETH), 100e6);
        WETH.deposit{value: assets}();
        WETH.approve(address(cellar), assets);
        cellar.depositIntoPosition(distrustedPosition, assets, address(this));

        // Simulate position gaining yield.
        MockERC4626(payable(address(distrustedPosition))).simulateGain(assets / 2, address(cellar));

        (, , uint112 balance) = cellar.getPositionData(distrustedPosition);
        assertEq(balance, assets);
        assertEq(cellar.totalBalance(), 100e6);
        assertEq(cellar.totalAssets(), 100e6);
        assertEq(cellar.totalHoldings(), 0);

        // Distrust and removing position.
        cellar.setTrust(distrustedPosition, false);

        // Test that assets have been pulled from untrusted position and state has updated accordingly.
        (, , balance) = cellar.getPositionData(distrustedPosition);
        assertEq(balance, 0);
        // Expected 142.5 assets to be received after swapping 150 assets with simulated 5% slippage.
        assertEq(cellar.totalBalance(), 0);
        assertEq(cellar.totalAssets(), 142.5e6);
        assertEq(cellar.totalHoldings(), 142.5e6);

        // Test that position has been distrusted.
        (bool isTrusted, , ) = cellar.getPositionData(distrustedPosition);
        assertFalse(isTrusted);

        // Test that position has been removed from list of positions.
        ERC4626[] memory expectedPositions = new ERC4626[](2);
        expectedPositions[0] = ERC4626(payable(address(usdcCLR)));
        expectedPositions[1] = ERC4626(payable(address(wbtcCLR)));

        ERC4626[] memory positions = cellar.getPositions();
        for (uint256 i; i < positions.length; i++) assertTrue(positions[i] == expectedPositions[i]);
    }

    // ============================================== SWEEP TEST ==============================================

    function testSweep() public {
        MockERC20 XYZ = new MockERC20("XYZ", 18);
        XYZ.mint(address(cellar), 100e18);

        // Test sweep.
        cellar.sweep(address(XYZ), 100e18, address(this));

        assertEq(XYZ.balanceOf(address(this)), 100e18);
    }

    function testFailSweep() public {
        wbtcCLR.mint(address(cellar), 100e18);

        // Test sweep of protected asset.
        cellar.sweep(address(wbtcCLR), 100e18, address(this));
    }

    function testFailAttemptingToStealFundsByRemovingPositionThenSweeping() public {
        // Deposit assets into position before distrusting.
        uint256 assets = swapRouter.convert(address(USDC), address(WBTC), 100e6);
        WBTC.mint(address(this), assets);
        WBTC.approve(address(cellar), assets);
        cellar.depositIntoPosition(wbtcCLR, assets, address(this));

        // Simulate position gaining yield.
        MockERC4626(payable(address(wbtcCLR))).simulateGain(assets / 2, address(cellar));

        uint256 totalAssets = assets + assets / 2;
        assertEq(wbtcCLR.balanceOf(address(cellar)), totalAssets);

        // Remove position.
        cellar.removePosition(wbtcCLR);

        assertEq(wbtcCLR.balanceOf(address(cellar)), 0);

        // Test attempting to steal assets after removing position from list.
        cellar.sweep(address(wbtcCLR), totalAssets, address(this));
    }

    // ============================================= EMERGENCY TEST =============================================

    function testFailShutdownDeposit() public {
        cellar.setShutdown(true, false);

        USDC.mint(address(this), 1);
        USDC.approve(address(cellar), 1);
        cellar.deposit(1, address(this));
    }

    function testFailShutdownDepositIntoPosition() public {
        USDC.mint(address(this), 1e18);
        USDC.approve(address(cellar), 1e18);
        cellar.deposit(1e18, address(this));

        cellar.setShutdown(true, false);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(USDC);

        cellar.rebalance(cellar, usdcCLR, 1e18, 0, path);
    }

    function testShutdownExitsAllPositions() public {
        // Deposit 100 assets into each position with 50 assets of unrealized yield.
        ERC4626[] memory positions = cellar.getPositions();
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];
            MockERC20 positionAsset = MockERC20(address(position.asset()));

            uint256 assets = swapRouter.convert(address(USDC), address(positionAsset), 100e6);
            positionAsset.mint(address(this), assets);
            positionAsset.approve(address(cellar), assets);
            cellar.depositIntoPosition(position, assets, address(this));

            MockERC4626(payable(address(position))).simulateGain(assets / 2, address(cellar));
        }

        assertApproxEq(cellar.totalBalance(), 300e6, 1e6);
        assertApproxEq(cellar.totalAssets(), 300e6, 1e6);
        assertEq(cellar.totalHoldings(), 0);

        cellar.setShutdown(true, true);

        assertTrue(cellar.isShutdown());
        assertEq(cellar.totalBalance(), 0);
        // Expect to receive 435 assets after 450 total assets from positions are swapped with 5% slippage.
        assertApproxEq(cellar.totalAssets(), 435e6, 2e6);
        assertApproxEq(cellar.totalHoldings(), 435e6, 2e6);
    }

    function testShutdownExitsAllPositionsWithNoBalances() public {
        cellar.setShutdown(true, true);

        assertTrue(cellar.isShutdown());
    }

    // ============================================== LIMITS TEST ==============================================

    function testLimits() public {
        USDC.mint(address(this), 100e6);
        USDC.approve(address(cellar), 100e6);
        cellar.deposit(100e6, address(this));

        assertEq(cellar.maxDeposit(address(this)), type(uint256).max);
        assertEq(cellar.maxMint(address(this)), type(uint256).max);

        cellar.setDepositLimit(200e6);
        cellar.setLiquidityLimit(100e6);

        assertEq(cellar.depositLimit(), 200e6);
        assertEq(cellar.liquidityLimit(), 100e6);
        assertEq(cellar.maxDeposit(address(this)), 0);
        assertEq(cellar.maxMint(address(this)), 0);

        cellar.setLiquidityLimit(300e6);

        assertEq(cellar.depositLimit(), 200e6);
        assertEq(cellar.liquidityLimit(), 300e6);
        assertEq(cellar.maxDeposit(address(this)), 100e6);
        assertEq(cellar.maxMint(address(this)), 100e6);

        cellar.setShutdown(true, false);

        assertEq(cellar.maxDeposit(address(this)), 0);
        assertEq(cellar.maxMint(address(this)), 0);
    }

    function testFailDepositAboveDepositLimit() public {
        cellar.setDepositLimit(100e6);

        USDC.mint(address(this), 101e6);
        USDC.approve(address(cellar), 101e6);
        cellar.deposit(101e6, address(this));
    }

    function testFailMintAboveDepositLimit() public {
        cellar.setDepositLimit(100e6);

        USDC.mint(address(this), 101e6);
        USDC.approve(address(cellar), 101e6);
        cellar.mint(101e6, address(this));
    }

    function testFailDepositAboveLiquidityLimit() public {
        cellar.setLiquidityLimit(100e6);

        USDC.mint(address(this), 101e6);
        USDC.approve(address(cellar), 101e6);
        cellar.deposit(101e6, address(this));
    }

    function testFailMintAboveLiquidityLimit() public {
        cellar.setLiquidityLimit(100e6);

        USDC.mint(address(this), 101e6);
        USDC.approve(address(cellar), 101e6);
        cellar.mint(101e6, address(this));
    }*/
    
    receive() external payable {}
}
