// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { Registry, PriceRouter, IGravity } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockExchange } from "src/mocks/MockExchange.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { LockedERC4626 } from "src/mocks/LockedERC4626.sol";
import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

// Will test the swapping and cellar position management using adaptors
contract CellarAssetManagerTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

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

    ERC20 private LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    address private immutable strategist = vm.addr(0xBEEF);

    address private immutable cosmos = vm.addr(0xCAAA);

    CellarAdaptor private cellarAdaptor;
    ERC20Adaptor private erc20Adaptor;

    uint32 private usdcPosition;
    uint32 private wethPosition;
    uint32 private usdcCLRPosition;
    uint32 private wethCLRPosition;
    uint32 private wbtcCLRPosition;

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
        cellarAdaptor = new CellarAdaptor();
        erc20Adaptor = new ERC20Adaptor();

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

        priceRouter.setExchangeRate(USDC, WBTC, 0.00003333e8);
        priceRouter.setExchangeRate(WBTC, USDC, 30_000e6);

        priceRouter.setExchangeRate(WETH, WBTC, 0.06666666e8);
        priceRouter.setExchangeRate(WBTC, WETH, 15e18);

        priceRouter.setPrice(USDC, 1e8);
        priceRouter.setPrice(WETH, 2_000e8);
        priceRouter.setPrice(WBTC, 30_000e8);

        priceRouter.supportAsset(USDC);
        priceRouter.supportAsset(WETH);
        priceRouter.supportAsset(WBTC);

        // Cellar positions array.
        uint32[] memory positions = new uint32[](5);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(cellarAdaptor), 0, 0);
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC), 0, 0);
        usdcCLRPosition = registry.trustPosition(address(cellarAdaptor), abi.encode(usdcCLR), 0, 0);
        wethCLRPosition = registry.trustPosition(address(cellarAdaptor), abi.encode(wethCLR), 0, 0);
        wbtcCLRPosition = registry.trustPosition(address(cellarAdaptor), abi.encode(wbtcCLR), 0, 0);
        wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH), 0, 0);

        positions[0] = usdcPosition;
        positions[1] = usdcCLRPosition;
        positions[2] = wethCLRPosition;
        positions[3] = wbtcCLRPosition;
        positions[4] = wethPosition;

        uint32[] memory debtPositions;

        bytes[] memory positionConfigs = new bytes[](5);

        bytes[] memory debtConfigs;

        cellar = new MockCellar(
            registry,
            USDC,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            abi.encode(positions, debtPositions, positionConfigs, debtConfigs, usdcPosition, strategist)
        );
        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Allow cellar to use CellarAdaptor so it can swap ERC20's and enter/leave other cellar positions.
        cellar.setupAdaptor(address(cellarAdaptor));

        cellar.setRebalanceDeviation(0.003e18);

        // Mint enough liquidity to swap router for swaps.
        deal(address(USDC), address(exchange), type(uint224).max);
        deal(address(WETH), address(exchange), type(uint224).max);
        deal(address(WBTC), address(exchange), type(uint224).max);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        WETH.approve(address(cellar), type(uint256).max);
        WBTC.approve(address(cellar), type(uint256).max);

        // Manipulate  test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    // ========================================== REBALANCE TEST ==========================================

    function testRebalanceBetweenCellarOrERC4626Positions(uint256 assets) external {
        assets = bound(assets, 1e6, type(uint72).max);

        // Update allowed rebalance deviation to work with mock swap router.
        cellar.setRebalanceDeviation(0.051e18);

        cellar.depositIntoPosition(usdcCLRPosition, assets);

        // Make call to adaptor to remove funds from usdcCLR into wethCLR position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](3);

        // First withdraw from the usdcCLR.
        adaptorCalls[0] = abi.encodeWithSelector(CellarAdaptor.withdrawFromCellar.selector, usdcCLR, assets);

        // Swap withdrawn assets into WETH.
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);
        bytes memory swapParams = abi.encode(path, assets, 0);
        adaptorCalls[1] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            WETH,
            assets,
            SwapRouter.Exchange.UNIV2,
            swapParams
        );

        // Deposit new WETH assets into wethCLR.
        adaptorCalls[2] = abi.encodeWithSelector(CellarAdaptor.depositToCellar.selector, wethCLR, type(uint256).max);

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(usdcCLR.balanceOf(address(cellar)), 0, "Should have rebalanced from position.");
        //assertEq(wethCLR.balanceOf(address(cellar)), assetsTo, "Should have rebalanced to position.");
        // assertEq(assetsTo, exchange.quote(assets, path), "Should received expected assets from swap.");
        // assertEq(usdcCLR.balanceOf(address(cellar)), 0, "Should have rebalanced from position.");
        // assertEq(wethCLR.balanceOf(address(cellar)), assetsTo, "Should have rebalanced to position.");
    }

    function testRebalanceBetweenERC20Positions(uint256 assets) external {
        assets = bound(assets, 1e6, type(uint72).max);

        // Update allowed rebalance deviation to work with mock swap router.
        cellar.setRebalanceDeviation(0.051e18);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), assets);

        // Deposit USDC into Cellar.
        cellar.deposit(assets, address(this));

        // Make call to adaptor to move funds from USDC into WETH position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Swap withdrawn assets into WETH.
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);
        bytes memory swapParams = abi.encode(path, assets, 0);
        adaptorCalls[0] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            WETH,
            assets,
            SwapRouter.Exchange.UNIV2,
            swapParams
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        //assertEq(assetsTo, exchange.quote(assets, path), "Should received expected assets from swap.");
        assertEq(USDC.balanceOf(address(cellar)), 0, "Should have rebalanced from position.");
        //assertEq(WETH.balanceOf(address(cellar)), assetsTo, "Should have rebalanced to position.");
    }

    function testRebalancingToInvalidPosition() external {
        uint256 assets = 100e6;
        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), assets);

        // Deposit USDC into Cellar.
        cellar.deposit(assets, address(this));

        // Make call to adaptor to move funds from USDC into WETH position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Swap withdrawn assets into WETH.
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WBTC); // WBTC is an untracked position.
        bytes memory swapParams = abi.encode(path, assets, 0);
        adaptorCalls[0] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            WBTC,
            assets,
            SwapRouter.Exchange.UNIV2,
            swapParams
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__TotalAssetDeviatedOutsideRange.selector,
                    0, // Since assets were moved to invalid position.
                    assets.mulDivUp(0.997e18, 1e18),
                    assets.mulWadDown(1.003e18)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // =========================================== TOTAL ASSETS TEST ===========================================

    function testTotalAssets(
        uint256 usdcAmount,
        uint256 usdcCLRAmount,
        uint256 wethCLRAmount,
        uint256 wbtcCLRAmount,
        uint256 wethAmount
    ) external {
        usdcAmount = bound(usdcAmount, 1e6, 1_000_000_000_000e6);
        usdcCLRAmount = bound(usdcCLRAmount, 1e6, 1_000_000_000_000e6);
        wethCLRAmount = bound(wethCLRAmount, 1e18, 200_000_000e18);
        wbtcCLRAmount = bound(wbtcCLRAmount, 1e8, 21_000_000e8);
        wethAmount = bound(wethAmount, 1e18, 200_000_000e18);
        uint256 totalAssets = cellar.totalAssets();

        assertEq(totalAssets, 0, "Cellar total assets should be zero.");

        cellar.depositIntoPosition(usdcCLRPosition, usdcCLRAmount);
        cellar.depositIntoPosition(wethCLRPosition, wethCLRAmount);
        cellar.depositIntoPosition(wbtcCLRPosition, wbtcCLRAmount);
        deal(address(WETH), address(cellar), wethAmount);
        deal(address(USDC), address(cellar), usdcAmount);

        uint256 expectedTotalAssets = usdcAmount + usdcCLRAmount;
        expectedTotalAssets += (wethAmount + wethCLRAmount).mulDivDown(2_000e6, 1e18);
        expectedTotalAssets += wbtcCLRAmount.mulDivDown(30_000e6, 1e8);

        totalAssets = cellar.totalAssets();

        assertApproxEqAbs(
            totalAssets,
            expectedTotalAssets,
            1,
            "`totalAssets` should equal all asset values summed together."
        );
    }

    function testRebalanceDeviation() external {
        uint256 assets = 100e6;

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), assets);

        // Deposit USDC into Cellar.
        cellar.deposit(assets, address(this));

        // Make call to adaptor to move funds from USDC into WETH position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Swap withdrawn assets into WETH.
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);
        bytes memory swapParams = abi.encode(path, assets, 0);
        adaptorCalls[0] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            WETH,
            assets,
            SwapRouter.Exchange.UNIV2,
            swapParams
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__TotalAssetDeviatedOutsideRange.selector,
                    assets.mulWadDown(0.95e18),
                    assets.mulDivUp(0.997e18, 1e18),
                    assets.mulWadDown(1.003e18)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRebalanceWithSharesMinted() external {
        // False specifies that this cellar tries to change the callers totalSupply on deposit calls.
        ReentrancyERC4626 maliciousCellar = new ReentrancyERC4626(USDC, "Bad Cellar", "BC", false);

        uint32 maliciousPosition = registry.trustPosition(
            address(cellarAdaptor),
            abi.encode(Cellar(address(maliciousCellar))),
            0,
            0
        );
        cellar.addPosition(5, maliciousPosition, abi.encode(0), false);

        uint256 assets = 10000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(maliciousCellar), assets);

        cellar.deposit(assets, address(this));

        // Make call to adaptor to move funds from `from` into `to` positions.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        Cellar toPosition = Cellar(address(maliciousCellar));
        adaptorCalls[0] = abi.encodeWithSelector(CellarAdaptor.depositToCellar.selector, toPosition, assets);

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });

        // Try to rebalance into malicous cellar that will change this cellars totalSupply.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__TotalSharesMustRemainConstant.selector,
                    cellar.totalSupply() + 1,
                    cellar.totalSupply()
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testMaliciousRebalanceIntoUntrackedPosition() external {
        // Create a new Cellar with two positions USDC, and WETH.
        // Setup Cellar:
        uint32[] memory positions = new uint32[](2);
        positions[0] = usdcPosition;
        positions[1] = wethPosition;

        uint32[] memory debtPositions;

        bytes[] memory positionConfigs = new bytes[](2);
        bytes[] memory debtConfigs;

        Cellar badCellar = new MockCellar(
            registry,
            USDC,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            abi.encode(positions, debtPositions, positionConfigs, debtConfigs, usdcPosition, strategist)
        );
        stdstore.target(address(badCellar)).sig(badCellar.shareLockPeriod.selector).checked_write(uint256(0));
        badCellar.setupAdaptor(address(cellarAdaptor));

        // User join bad cellar.
        address alice = vm.addr(77777);
        deal(address(USDC), alice, 1_000_000e6);
        vm.startPrank(alice);
        USDC.approve(address(badCellar), 1_000_000e6);
        badCellar.deposit(1_000_000e6, alice);
        vm.stopPrank();

        // Strategist calls rebalance with malicious swap data.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WBTC);
        uint256 amount = 500_000e6;

        bytes memory swapParams = abi.encode(path, amount, 0);
        adaptorCalls[0] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            WETH,
            amount,
            SwapRouter.Exchange.UNIV2,
            swapParams
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(SwapRouter.SwapRouter__AssetOutMisMatch.selector, address(WBTC), address(WETH))
            )
        );
        badCellar.callOnAdaptor(data);
    }

    function testMaliciousStrategistFundsLocked() external {
        LockedERC4626 maliciousCellar = new LockedERC4626(USDC, "Bad Cellar", "BC", 1e18);

        uint32 maliciousPosition = registry.trustPosition(
            address(cellarAdaptor),
            abi.encode(Cellar(address(maliciousCellar))),
            0,
            0
        );
        cellar.addPosition(5, maliciousPosition, abi.encode(0), false);

        // Deposit into cellar.
        uint256 assets = 10000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(maliciousCellar), assets);
        cellar.deposit(assets, address(this));

        uint256 totalAssetsBefore = cellar.totalAssets();

        // Rebalance USDC deposit into maliciousCellar.
        _rebalanceWithERC4626Positions(cellar, USDC, ERC20(address(maliciousCellar)), 1e6);
        // cellar.rebalance(address(USDC), address(maliciousCellar), 1e6, SwapRouter.Exchange.UNIV2, abi.encode(0));

        uint256 totalAssetsAfter = cellar.totalAssets();
        // Eventhough withdrawable amount is assets -1, totalAssets should not change from rebalance.
        assertEq(totalAssetsAfter, totalAssetsBefore, "Total assets should not change from rebalance call.");

        // User still can not withdraw all assets since some of them are still locked.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__IncompleteWithdraw.selector, 1e6)));
        cellar.withdraw(assets, address(this), address(this));

        // User can withdraw all their assets except for assets locked.
        cellar.withdraw(assets - 1e6, address(this), address(this));
    }

    function createCellarWithLockedFunds(uint256 assets)
        internal
        returns (
            MockCellar,
            LockedERC4626,
            LockedERC4626
        )
    {
        // New Cellar with positions in USDC, locked USDC, locked WETH, and  WETH
        LockedERC4626 lockedUSDC = new LockedERC4626(USDC, "Locked USDC", "LUSDC", 0.9e18); // 90% of funds are locked.
        LockedERC4626 lockedWETH = new LockedERC4626(WETH, "Locked WETH", "LWETH", 1e18); // 100% of funds are locked

        MockCellar cellarWithLockedFunds;
        // Setup Cellar:
        {
            uint32[] memory positions = new uint32[](4);
            positions[0] = usdcPosition;
            positions[1] = registry.trustPosition(
                address(cellarAdaptor),
                abi.encode(Cellar(address(lockedUSDC))),
                0,
                0
            );
            positions[2] = registry.trustPosition(
                address(cellarAdaptor),
                abi.encode(Cellar(address(lockedWETH))),
                0,
                0
            );
            positions[3] = wethPosition;

            uint32[] memory debtPositions;

            bytes[] memory positionConfigs = new bytes[](4);

            bytes[] memory debtConfigs;

            cellarWithLockedFunds = new MockCellar(
                registry,
                USDC,
                "Multiposition Cellar LP Token",
                "multiposition-CLR",
                abi.encode(positions, debtPositions, positionConfigs, debtConfigs, usdcPosition, strategist)
            );
        }

        cellarWithLockedFunds.setupAdaptor(address(cellarAdaptor));
        stdstore
            .target(address(cellarWithLockedFunds))
            .sig(cellarWithLockedFunds.shareLockPeriod.selector)
            .checked_write(uint256(0));

        // Make initial deposit into cellar.
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellarWithLockedFunds), assets);
        cellarWithLockedFunds.deposit(assets, address(this));

        // Rebalance so 25% of assets are in each position.
        deal(address(USDC), address(cellarWithLockedFunds), assets / 2);

        uint256 WETHAssets = priceRouter.getValue(USDC, assets / 2, WETH);
        deal(address(WETH), address(cellarWithLockedFunds), WETHAssets);

        _rebalanceWithERC4626Positions(cellarWithLockedFunds, USDC, ERC20(address(lockedUSDC)), assets / 4);
        _rebalanceWithERC4626Positions(cellarWithLockedFunds, WETH, ERC20(address(lockedWETH)), WETHAssets / 2);

        assertEq(
            cellarWithLockedFunds.totalAssets(),
            assets,
            "Total assets should not have been changed during rebalance."
        );

        assertEq(cellarWithLockedFunds.totalAssetsWithdrawable(), assets.mulWadDown(0.525e18));

        return (cellarWithLockedFunds, lockedUSDC, lockedWETH);
    }

    function testCellarLockedAssetsOrderlyWithdraw() external {
        uint256 assets = 1_000_000e6;
        (MockCellar testCellar, , ) = createCellarWithLockedFunds(assets);

        assertEq(testCellar.maxWithdraw(address(this)), assets.mulWadDown(0.525e18));
        assertEq(testCellar.totalAssetsWithdrawable(), assets.mulWadDown(0.525e18));

        // User redeems 50% of their shares.
        testCellar.withdraw(assets / 2, address(this), address(this));

        // User should now have 27.5% of assets in USDC, and 22.5% of assets in WETH.
        assertEq(USDC.balanceOf(address(this)), assets.mulWadDown(0.275e18), "USDC balance should be 27.5% of assets.");
        uint256 WETHAssetsInUSDC = priceRouter.getValue(WETH, WETH.balanceOf(address(this)), USDC);
        assertEq(WETHAssetsInUSDC, assets.mulWadDown(0.225e18), "WETH balance should be 22.5% of assets.");

        assertEq(testCellar.totalAssets(), assets.mulWadDown(0.5e18), "Total assets should have decreased by 50%.");
    }

    function testMaxWithdraw() external {
        uint256 assets = 1_000_000e6;
        (MockCellar testCellar, , LockedERC4626 lockedWETH) = createCellarWithLockedFunds(assets);
        uint256 expectedMaxWithdraw = assets.mulWadDown(0.525e18);
        assertEq(testCellar.maxWithdraw(address(this)), expectedMaxWithdraw, "Max withdraw should equal expected.");

        // Rebalance funds from lockedWETH to WETH.
        _rebalanceWithERC4626Positions(
            testCellar,
            ERC20(address(lockedWETH)),
            WETH,
            WETH.balanceOf(address(lockedWETH))
        );

        expectedMaxWithdraw = assets.mulWadDown(0.775e18);
        assertEq(testCellar.maxWithdraw(address(this)), expectedMaxWithdraw, "Max withdraw should equal expected.");

        // Give another user some shares worth less than 2.5% of assets.
        address otherUser = vm.addr(7777);
        uint256 shares = testCellar.convertToShares(assets.mulWadDown(0.02e18));
        testCellar.transfer(otherUser, shares);

        expectedMaxWithdraw = assets.mulWadDown(0.02e18);
        assertEq(testCellar.maxWithdraw(otherUser), expectedMaxWithdraw, "Max withdraw should equal expected..");

        expectedMaxWithdraw = assets.mulWadDown(0.775e18);
        assertEq(testCellar.maxWithdraw(address(this)), expectedMaxWithdraw, "Max withdraw should equal expected..");
    }

    function testFindMax() external {
        uint256 deposit = 1e6;

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), type(uint256).max);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // No yield has been earned.
        assertEq(cellar.maxWithdraw(address(this)), deposit, "Max withdraw should equal deposit.");
        uint256 expectedShares = 1e18;
        assertEq(cellar.maxRedeem(address(this)), expectedShares, "Max Redeem should be 1 share.");

        // Simulate yield.
        deal(address(USDC), address(cellar), 10e6);

        uint256 expectedAssets = 10e6; // initial $1 deposit + $9 of yield - 10% performance fees.
        assertEq(cellar.maxWithdraw(address(this)), expectedAssets, "Max withdraw should equal deposit + yield.");
        assertEq(cellar.maxRedeem(address(this)), expectedShares, "Max Redeem should be 1 share.");

        // Strategist moves half of funds into an illiquid position.
        LockedERC4626 lockedUSDC = new LockedERC4626(USDC, "Locked USDC", "LUSDC", 1e18); // 100% of funds are locked.
        uint32 lockedUSDCPosition = registry.trustPosition(address(cellarAdaptor), abi.encode(lockedUSDC), 0, 0);
        cellar.addPosition(5, lockedUSDCPosition, abi.encode(0), false);

        // Strategist rebalances into illiquid cellar.
        _rebalanceWithERC4626Positions(cellar, USDC, ERC20(address(lockedUSDC)), 5e6);

        assertEq(cellar.totalAssets(), 10e6, "Total assets should not have changed.");

        expectedAssets = 5e6; // Half the assets are locked, so maxWithdraw should be half of deposit + yield.
        expectedShares = cellar.previewWithdraw(expectedAssets);
        assertEq(cellar.maxWithdraw(address(this)), expectedAssets, "Max withdraw should equal expectedAssets.");
        assertApproxEqAbs(
            cellar.maxRedeem(address(this)),
            expectedShares,
            1,
            "Max Redeem should equal previewRedeem(maxWithdraw(user))."
        );
    }

    // ======================================== INTEGRATION TESTS ========================================

    uint256 public saltIndex;

    /**
     * @notice Generates a random number between 1 and 1e9.
     */
    function _mutate(uint256 salt) internal returns (uint256) {
        saltIndex++;
        uint256 random = uint256(keccak256(abi.encode(salt, saltIndex)));
        random = bound(random, 1, 1_000_000_000);
        return random;
    }

    function _changeMarketPrices(ERC20[] memory assetsToAdjust, uint256[] memory newPricesInUSD) internal {
        uint256 quoteIndex;
        uint256 exchangeRate;
        for (uint256 i = 0; i < assetsToAdjust.length; i++) {
            for (uint256 j = 1; j < assetsToAdjust.length; j++) {
                quoteIndex = i + j;
                if (quoteIndex >= assetsToAdjust.length) quoteIndex -= assetsToAdjust.length;
                exchangeRate = (10**assetsToAdjust[quoteIndex].decimals()).mulDivDown(
                    newPricesInUSD[i],
                    newPricesInUSD[quoteIndex]
                );
                priceRouter.setExchangeRate(assetsToAdjust[i], assetsToAdjust[quoteIndex], exchangeRate);
                priceRouter.setPrice(assetsToAdjust[i], newPricesInUSD[i]);
            }
        }
    }

    enum Action {
        DEPOSIT,
        MINT,
        WITHDRAW,
        REDEEM
    }

    /**
     * @notice Helper function that performs 1 of 4 user actions.
     *         Validates that the preview function returns the same as the actual function.
     * @param target Cellar to work with.
     * @param user Address that is performing the action.
     * @param action Enum dictating what `Action` is performed.
     * @param amountOfAssets to deposit/withdraw to/from the cellar.
      @param amountOfShares to mint/redeem to/from the cellar.
     */
    function _userAction(
        Cellar target,
        address user,
        Action action,
        uint256 amountOfAssets,
        uint256 amountOfShares
    ) internal returns (uint256 assets, uint256 shares) {
        vm.startPrank(user);
        if (action == Action.DEPOSIT) {
            assets = amountOfAssets;
            assertApproxEqAbs(
                target.previewDeposit(amountOfAssets),
                shares = target.deposit(amountOfAssets, user),
                200, // When the amount being deposited is much larger than the TVL, because of how the preview deposit function works, there is much worse precision.
                "Deposit should be equal to previewDeposit"
            );
        } else if (action == Action.WITHDRAW) {
            assets = amountOfAssets;
            assertApproxEqAbs(
                target.previewWithdraw(amountOfAssets),
                shares = target.withdraw(amountOfAssets, user, user),
                10,
                "Withdraw should be equal to previewWithdraw"
            );
        } else if (action == Action.MINT) {
            shares = amountOfShares;
            assertApproxEqAbs(
                target.previewMint(amountOfShares),
                assets = target.mint(amountOfShares, user),
                10,
                "Mint should be equal to previewMint"
            );
        } else if (action == Action.REDEEM) {
            shares = amountOfShares;
            assertApproxEqAbs(
                target.previewRedeem(amountOfShares),
                assets = target.redeem(amountOfShares, user, user),
                10,
                "Redeem should be equal to previewRedeem"
            );
        }
        vm.stopPrank();
    }

    /**
     * @notice Helper function that calls `rebalance` for a cellar.
     * @param target Cellar to call `rebalance` on.
     * @param from Token to sell.
     * @param to Token to buy.
     * @param amount The amount of `from` token to sell.
     */
    function _rebalance(
        Cellar target,
        ERC20 from,
        ERC20 to,
        uint256 amount
    ) internal returns (uint256 assetsTo) {
        // Make call to adaptor to move funds from `from` into `to` positions.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Swap withdrawn assets into WETH.
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        bytes memory swapParams = abi.encode(path, amount, 0);
        adaptorCalls[0] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            from,
            to,
            amount,
            SwapRouter.Exchange.UNIV2,
            swapParams
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        uint256 toBalance = to.balanceOf(address(target));
        target.callOnAdaptor(data);
        assetsTo = to.balanceOf(address(target)) - toBalance;
    }

    /**
     * @notice Helper function that calls `rebalance` for a cellar.
     * @param target Cellar to call `rebalance` on.
     * @param from Token to sell.
     * @param to Token to buy.
     * @param amount The amount of `from` token to sell.
     */
    function _rebalanceWithERC4626Positions(
        Cellar target,
        ERC20 from,
        ERC20 to,
        uint256 amount
    ) internal returns (uint256) {
        // Make call to adaptor to move funds from `from` into `to` positions.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // See if `from` is an ERC4626 or an ERC20
        Cellar fromPosition = Cellar(address(from));
        try fromPosition.totalAssets() returns (uint256) {
            // From position is an ERC4626.
            adaptorCalls[0] = abi.encodeWithSelector(CellarAdaptor.withdrawFromCellar.selector, fromPosition, amount);
        } catch {
            // To position is an ERC4626.
            Cellar toPosition = Cellar(address(to));
            adaptorCalls[0] = abi.encodeWithSelector(CellarAdaptor.depositToCellar.selector, toPosition, amount);
        }

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });

        target.callOnAdaptor(data);
        return amount;
    }

    /**
     * @notice Helper function that calls `sendFees` for a cellar, and validates
     *         performance fees, platform fees, and destination of them.
     * @param target Cellar to call `sendFees` on.
     * @param amountOfTimeToPass How much time should pass before `sendFees` is called.
     */
    function _checkSendFees(Cellar target, uint256 amountOfTimeToPass) internal {
        skip(amountOfTimeToPass);

        (, uint64 platformFee, , address strategistPayoutAddress) = target.feeData();

        uint256 cellarTotalAssets = target.totalAssets();
        uint256 feesInAssetsSentToCosmos;
        uint256 feesInAssetsSentToStrategist;
        {
            uint256 cosmosFeeInAssetBefore = target.asset().balanceOf(cosmos);
            uint256 strategistFeeSharesBefore = target.balanceOf(strategistPayoutAddress);

            target.sendFees();

            feesInAssetsSentToCosmos = target.asset().balanceOf(cosmos) - cosmosFeeInAssetBefore;
            feesInAssetsSentToStrategist = target.previewRedeem(
                target.balanceOf(strategistPayoutAddress) - strategistFeeSharesBefore
            );
        }
        uint256 expectedPlatformFeeInAssets;

        expectedPlatformFeeInAssets = (cellarTotalAssets * platformFee * amountOfTimeToPass) / 1e18 / 365 days;

        assertApproxEqRel(
            feesInAssetsSentToCosmos + feesInAssetsSentToStrategist,
            expectedPlatformFeeInAssets,
            0.0000001e18,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected total fees after dilution."
        );

        (uint64 strategistPlatformCut, , , ) = target.feeData();

        assertApproxEqRel(
            feesInAssetsSentToStrategist,
            expectedPlatformFeeInAssets.mulWadDown(strategistPlatformCut),
            0.0000001e18,
            "Shares converted to assets sent to strategist should be equal to (total platform fees * strategistPlatformCut)."
        );
        assertApproxEqRel(
            feesInAssetsSentToCosmos,
            expectedPlatformFeeInAssets.mulWadDown(1e18 - strategistPlatformCut),
            0.0000001e18,
            "Assets sent to Cosmos should be equal to (total platform fees * (1-strategistPlatformCut))."
        );
    }

    /**
     * @notice Calculates the minimum assets required to complete sendFees call.
     */
    function previewAssetMinimumsForSendFee(Cellar target, uint256 amountOfTimeToPass)
        public
        view
        returns (uint256 assetReq)
    {
        (uint64 strategistPlatformCut, uint64 platformFee, , ) = target.feeData();

        uint256 expectedPlatformFeeInAssets;
        uint256 cellarTotalAssets = target.totalAssets();

        expectedPlatformFeeInAssets = (cellarTotalAssets * platformFee * amountOfTimeToPass) / (365 days * 1e18);

        assetReq =
            expectedPlatformFeeInAssets.mulWadDown(1e18 - strategistPlatformCut) +
            // Add an extra asset to account for rounding errors, and insure
            // cellar has enough to cover sendFees.
            10**target.asset().decimals();
    }

    function _ensureEnoughAssetsToCoverSendFees(
        Cellar target,
        uint256 amountOfTimeToPass,
        ERC20 assetToTakeFrom
    ) internal {
        {
            ERC20 asset = target.asset();
            uint256 assetsReq = previewAssetMinimumsForSendFee(target, amountOfTimeToPass);
            uint256 cellarAssetBalance = asset.balanceOf(address(target));
            if (assetsReq > cellarAssetBalance) {
                // Mint cellar enough asset to cover sendFees.
                uint256 totalAssets = target.totalAssets();

                // Remove added value from assetToTakeFrom position to preserve totalAssets().
                assetsReq = assetsReq - cellarAssetBalance;
                uint256 remove = priceRouter.getValue(asset, assetsReq, assetToTakeFrom);
                deal(address(assetToTakeFrom), address(target), assetToTakeFrom.balanceOf(address(target)) - remove);

                deal(address(asset), address(target), cellarAssetBalance + totalAssets - target.totalAssets());
                assertEq(totalAssets, target.totalAssets(), "Function should not change the totalAssets.");
            }
        }
    }

    function testMultipleMintDepositRedeemWithdrawWithGainsLossAndSendFees(uint8 salt) external {
        // Initialize users.
        address alice = vm.addr(1);
        address bob = vm.addr(2);
        address sam = vm.addr(3);
        address mary = vm.addr(4);

        // Initialize test Cellar.
        MockCellar assetManagementCellar;
        {
            // Add wBTC position to registry.
            uint32 wbtcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WBTC), 0, 0);

            // Create new cellar with WETH, USDC, and WBTC positions.
            uint32[] memory positions = new uint32[](3);
            positions[0] = usdcPosition;
            positions[1] = wethPosition;
            positions[2] = wbtcPosition;

            uint32[] memory debtPositions;

            bytes[] memory positionConfigs = new bytes[](3);
            bytes[] memory debtConfigs;

            assetManagementCellar = new MockCellar(
                registry,
                USDC,
                "Asset Management Cellar LP Token",
                "assetmanagement-CLR",
                abi.encode(positions, debtPositions, positionConfigs, debtConfigs, usdcPosition, strategist)
            );
        }

        // Update allowed rebalance deviation to work with mock swap router.
        assetManagementCellar.setRebalanceDeviation(0.05e18);

        stdstore
            .target(address(assetManagementCellar))
            .sig(assetManagementCellar.shareLockPeriod.selector)
            .checked_write(uint256(0));

        assetManagementCellar.setupAdaptor(address(cellarAdaptor));

        // Give users USDC to interact with the Cellar.
        deal(address(USDC), alice, type(uint256).max);
        deal(address(USDC), bob, type(uint256).max);
        deal(address(USDC), sam, type(uint256).max);
        deal(address(USDC), mary, type(uint256).max);

        // Approve cellar to send user assets.
        vm.prank(alice);
        USDC.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(bob);
        USDC.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(sam);
        USDC.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(mary);
        USDC.approve(address(assetManagementCellar), type(uint256).max);

        // ====================== BEGIN SCENERIO ======================

        // Users join  cellar, cellar rebalances into WETH and WBTC positions, and sendFees is called.
        {
            uint256 amount = _mutate(salt) * 1e6;
            uint256 shares;
            uint256 assets;

            // Alice joins cellar using deposit.
            (assets, shares) = _userAction(assetManagementCellar, alice, Action.DEPOSIT, amount, 0);
            assertEq(shares, assetManagementCellar.balanceOf(alice), "Alice should have got shares out from deposit.");

            // Bob joins cellar using Mint.
            uint256 bobAssets = USDC.balanceOf(bob);
            (assets, shares) = _userAction(assetManagementCellar, bob, Action.MINT, 0, shares);
            assertEq(
                assets,
                bobAssets - USDC.balanceOf(bob),
                "Bob should have `amount` of assets taken from his address."
            );

            // Sam joins cellar with deposit, withdraws half his assets, then adds them back in using mint.
            (assets, shares) = _userAction(assetManagementCellar, sam, Action.DEPOSIT, amount, 0);
            (assets, shares) = _userAction(assetManagementCellar, sam, Action.WITHDRAW, amount / 2, 0);
            (assets, shares) = _userAction(assetManagementCellar, sam, Action.MINT, 0, shares);
        }
        {
            // Strategy providers swaps into WETH and WBTC using USDC, targeting a 20/40/40 split(USDC/WETH/WBTC).
            uint256 totalAssets = assetManagementCellar.totalAssets();

            // Swap 40% of Cellars USDC for WETH.
            uint256 usdcToSell = totalAssets.mulDivDown(4, 10);
            _rebalance(assetManagementCellar, USDC, WETH, usdcToSell);

            // Swap 40% of Cellars USDC for WBTC.
            _rebalance(assetManagementCellar, USDC, WBTC, usdcToSell);
        }

        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 7 days, WETH);
        _checkSendFees(assetManagementCellar, 7 days);

        // WBTC price increases enough to create yield, Mary joins the cellar, and sendFees is called.
        {
            // WBTC price goes up.

            ERC20[] memory assetsToAdjust = new ERC20[](3);
            uint256[] memory prices = new uint256[](3);
            assetsToAdjust[0] = USDC;
            assetsToAdjust[1] = WETH;
            assetsToAdjust[2] = WBTC;
            prices[0] = 1e8;
            prices[1] = 2_000e8;
            prices[2] = 45_000e8;
            _changeMarketPrices(assetsToAdjust, prices);
        }
        {
            uint256 amount = _mutate(salt) * 1e6;
            uint256 shares;
            uint256 assets;

            // Mary joins cellar using deposit.
            (assets, shares) = _userAction(assetManagementCellar, mary, Action.DEPOSIT, amount, 0);
        }
        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 7 days, WETH);
        _checkSendFees(assetManagementCellar, 7 days);

        // Adjust fee variables, lower WBTC price but raise WETH price enough to
        // create yield, rebalance all positions into WETH, Bob and Sam join
        // cellar, and sendFees is called.
        {
            // Set platform fee to 2%.
            assetManagementCellar.setPlatformFee(0.02e18);

            // Set strategist platform cut to 80%.
            assetManagementCellar.setStrategistPlatformCut(0.8e18);

            // Strategist rebalances all positions to only WETH
            uint256 assetBalanceToRemove = USDC.balanceOf(address(assetManagementCellar));
            _rebalance(assetManagementCellar, USDC, WETH, assetBalanceToRemove);

            assetBalanceToRemove = WBTC.balanceOf(address(assetManagementCellar));
            _rebalance(assetManagementCellar, WBTC, WETH, assetBalanceToRemove);

            // WBTC price goes down. WETH price goes up enough to create yield.
            {
                ERC20[] memory assetsToAdjust = new ERC20[](3);
                uint256[] memory prices = new uint256[](3);
                assetsToAdjust[0] = USDC;
                assetsToAdjust[1] = WETH;
                assetsToAdjust[2] = WBTC;
                prices[0] = 1e8;
                prices[1] = 4_000e8;
                prices[2] = 30_000e8;
                _changeMarketPrices(assetsToAdjust, prices);
            }
        }
        {
            // Bob enters cellar via `mint`.
            uint256 shares = _mutate(salt) * 1e18;

            deal(address(USDC), bob, type(uint256).max);
            (, shares) = _userAction(assetManagementCellar, bob, Action.MINT, 0, shares);
            deal(address(USDC), bob, 0);
            deal(address(USDC), sam, type(uint256).max);
            (, shares) = _userAction(assetManagementCellar, sam, Action.MINT, 0, shares);
            deal(address(USDC), sam, 0);

            _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 21 days, WETH);
            _checkSendFees(assetManagementCellar, 21 days);
        }

        // No yield was earned, and 28 days pass.
        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 28 days, WETH);
        _checkSendFees(assetManagementCellar, 28 days);

        // WETH price decreases, rebalance cellar so that USDC in Cellar can not
        // cover Alice's redeem. Alice redeems shares, and call sendFees.
        {
            //===== Start Bear Market ====
            // ETH price goes down.
            {
                ERC20[] memory assetsToAdjust = new ERC20[](3);
                uint256[] memory prices = new uint256[](3);
                assetsToAdjust[0] = USDC;
                assetsToAdjust[1] = WETH;
                assetsToAdjust[2] = WBTC;
                prices[0] = 1e8;
                prices[1] = 3_000e8;
                prices[2] = 30_000e8;
                _changeMarketPrices(assetsToAdjust, prices);
            }

            // Cellar has liquidity in USDC and WETH, rebalance cellar so it
            // must take from USDC, and WETH position to cover Alice's redeem.
            uint256 shares = assetManagementCellar.balanceOf(alice);
            uint256 assets = assetManagementCellar.previewRedeem(shares);

            // Manually rebalance Cellar so that it only has 10% of assets needed for Alice's Redeem.
            {
                uint256 targetUSDCBalance = assets / 10;
                uint256 currentUSDCBalance = USDC.balanceOf(address(assetManagementCellar));
                uint256 totalAssets = assetManagementCellar.totalAssets();
                deal(address(USDC), address(assetManagementCellar), 0);
                if (targetUSDCBalance > currentUSDCBalance) {
                    // Need to move assets too USDC.
                    uint256 wethToRemove = priceRouter.getValue(USDC, (targetUSDCBalance - currentUSDCBalance), WETH);
                    deal(
                        address(WETH),
                        address(assetManagementCellar),
                        WETH.balanceOf(address(assetManagementCellar)) - wethToRemove
                    );
                } else if (targetUSDCBalance < currentUSDCBalance) {
                    // Need to move assets from USDC.
                    uint256 wethToAdd = priceRouter.getValue(USDC, (currentUSDCBalance - targetUSDCBalance), WETH);
                    deal(
                        address(WETH),
                        address(assetManagementCellar),
                        WETH.balanceOf(address(assetManagementCellar)) + wethToAdd
                    );
                }
                // Give cellar target USDC Balance such that total assets remains unchanged.
                deal(address(USDC), address(assetManagementCellar), totalAssets - assetManagementCellar.totalAssets());

                assertEq(
                    assetManagementCellar.totalAssets(),
                    totalAssets,
                    "Cellar total assets should not be changed."
                );
            }

            uint256 assetsForShares = assetManagementCellar.convertToAssets(shares);

            // Set Alice's USDC balance to zero to avoid overflow on transfer.
            deal(address(USDC), alice, 0);

            // Alice redeems her shares.
            (assets, shares) = _userAction(assetManagementCellar, alice, Action.REDEEM, 0, shares);
            assertEq(assetsForShares, assets, "Assets out should be worth assetsForShares.");
            assertTrue(USDC.balanceOf(alice) > 0, "Alice should have gotten USDC.");
            assertTrue(WETH.balanceOf(alice) > 0, "Alice should have gotten WETH.");
            assertEq(WBTC.balanceOf(alice), 0, "Alice should not have gotten WBTC.");
            uint256 WETHworth = priceRouter.getValue(WETH, WETH.balanceOf(alice), USDC);
            assertApproxEqAbs(USDC.balanceOf(alice) + WETHworth, assets, 1, "Value of assets out should equal assets.");
        }

        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 7 days, WETH);
        _checkSendFees(assetManagementCellar, 7 days);

        // Alice rejoins cellar, call sendFees.
        {
            // Alice rejoins via mint.
            uint256 sharesToMint = _mutate(salt) * 1e18;
            deal(address(USDC), alice, assetManagementCellar.previewMint(sharesToMint));
            _userAction(assetManagementCellar, alice, Action.MINT, 0, sharesToMint);
        }

        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 1 days, WETH);
        _checkSendFees(assetManagementCellar, 1 days);

        // Rebalance cellar to move assets from WETH to WBTC.
        _rebalance(assetManagementCellar, WETH, WBTC, WETH.balanceOf(address(assetManagementCellar)) / 2);

        {
            // WBTC goes up a little, USDC depeggs to 0.95.

            ERC20[] memory assetsToAdjust = new ERC20[](3);
            uint256[] memory prices = new uint256[](3);
            assetsToAdjust[0] = USDC;
            assetsToAdjust[1] = WETH;
            assetsToAdjust[2] = WBTC;
            prices[0] = 0.95e8;
            prices[1] = 2_700e8;
            prices[2] = 45_000e8;
            _changeMarketPrices(assetsToAdjust, prices);

            _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 14 days, WETH);
            _checkSendFees(assetManagementCellar, 14 days);

            // Strategists trusts LINK, and then adds it as a position.
            // No need to set LINK price since its assets will always be zero.
            priceRouter.supportAsset(LINK);
            uint32 linkPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(LINK), 0, 0);

            assetManagementCellar.addPosition(3, linkPosition, abi.encode(0), false);

            // Swap LINK position with WETH position.
            assetManagementCellar.swapPositions(3, 1, false);

            // Adjust asset prices such that the cellar's TVL drops below the high watermark.

            assetsToAdjust = new ERC20[](3);
            prices = new uint256[](3);
            assetsToAdjust[0] = USDC;
            assetsToAdjust[1] = WETH;
            assetsToAdjust[2] = WBTC;
            prices[0] = 0.97e8;
            prices[1] = 2_900e8;
            prices[2] = 30_000e8;
            _changeMarketPrices(assetsToAdjust, prices);

            _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 7 days, WETH);
            _checkSendFees(assetManagementCellar, 7 days);
        }
        {
            // Change price of assets to make manual rebalances easier.
            ERC20[] memory assetsToAdjust = new ERC20[](3);
            uint256[] memory prices = new uint256[](3);
            assetsToAdjust[0] = USDC;
            assetsToAdjust[1] = WETH;
            assetsToAdjust[2] = WBTC;
            prices[0] = 1e8;
            prices[1] = 1_000e8;
            prices[2] = 10_000e8;
            _changeMarketPrices(assetsToAdjust, prices);
        }

        // Have everyone completely exit cellar.
        _userAction(assetManagementCellar, alice, Action.REDEEM, 0, assetManagementCellar.balanceOf(alice));
        _userAction(assetManagementCellar, bob, Action.REDEEM, 0, assetManagementCellar.balanceOf(bob));
        _userAction(assetManagementCellar, sam, Action.REDEEM, 0, assetManagementCellar.balanceOf(sam));

        // Mary has a ton of USDC from the initial deal, zero out her balance so
        // she can redeem her shares.
        deal(address(USDC), mary, 0);
        _userAction(assetManagementCellar, mary, Action.REDEEM, 0, assetManagementCellar.balanceOf(mary));
        _userAction(assetManagementCellar, strategist, Action.REDEEM, 0, assetManagementCellar.balanceOf(strategist));

        assertEq(assetManagementCellar.totalSupply(), 0, "All cellar shares should be burned.");
        assertEq(assetManagementCellar.totalAssets(), 0, "All cellar assets should be removed.");

        //Have everyone join with the same amount of assets.
        uint256 assetsNeeded = _mutate(salt) * 1e6;
        uint256 sharesToJoinWith = assetManagementCellar.convertToShares(assetsNeeded);

        deal(address(USDC), alice, assetsNeeded);
        deal(address(WETH), alice, 0);
        deal(address(WBTC), alice, 0);
        _userAction(assetManagementCellar, alice, Action.DEPOSIT, assetsNeeded, 0);

        deal(address(USDC), bob, assetsNeeded);
        deal(address(WBTC), bob, 0);
        deal(address(WETH), bob, 0);
        _userAction(assetManagementCellar, bob, Action.DEPOSIT, assetsNeeded, 0);

        deal(address(USDC), sam, assetsNeeded);
        deal(address(WBTC), sam, 0);
        deal(address(WETH), sam, 0);
        _userAction(assetManagementCellar, sam, Action.DEPOSIT, assetsNeeded, 0);

        deal(address(USDC), mary, assetsNeeded);
        deal(address(WBTC), mary, 0);
        deal(address(WETH), mary, 0);
        _userAction(assetManagementCellar, mary, Action.DEPOSIT, assetsNeeded, 0);

        // Shutdown the cellar.
        assetManagementCellar.initiateShutdown();

        // At this point we know all 4 cellar users have 25% of the shares each.

        // Manually rebalance assets like so LINK/WETH/WBTC/USDC 0/10/0/90.
        deal(address(LINK), address(assetManagementCellar), 0);
        deal(address(WBTC), address(assetManagementCellar), 0);
        deal(address(USDC), address(assetManagementCellar), (4 * assetsNeeded).mulDivDown(9, 10));
        deal(address(WETH), address(assetManagementCellar), ((4 * assetsNeeded) / 10000).changeDecimals(6, 18));

        // Have Alice exit using withdraw.
        _userAction(assetManagementCellar, alice, Action.WITHDRAW, assetsNeeded, 0);

        // Have Bob exit using redeem.
        _userAction(assetManagementCellar, bob, Action.REDEEM, 0, sharesToJoinWith);

        // Rebalance asses like so LINK/WETH/WBTC/USDC 0/10/45/45
        deal(address(LINK), address(assetManagementCellar), 0);

        // Set WBTC balance in cellar to equal 45% of the cellars total assets.
        deal(address(WBTC), address(assetManagementCellar), ((2 * assetsNeeded * 45) / 1000000).changeDecimals(6, 8));
        deal(address(USDC), address(assetManagementCellar), (2 * assetsNeeded).mulDivDown(1, 10));

        // Set WETH balance in cellar to equal 45% of the cellars total assets.
        deal(address(WETH), address(assetManagementCellar), ((2 * assetsNeeded * 45) / 100000).changeDecimals(6, 18));

        // Have Sam exit using withdraw.
        _userAction(assetManagementCellar, sam, Action.WITHDRAW, assetsNeeded, 0);

        // Have Mary exit using redeem.
        _userAction(assetManagementCellar, mary, Action.REDEEM, 0, sharesToJoinWith);

        // The total value we expect each user to have after redeeming their shares.
        uint256 expectedValue = assetsNeeded;

        // Alice should have some WETH and USDC.
        {
            uint256 aliceUSDCBalance = USDC.balanceOf(alice);
            uint256 aliceWETHBalance = WETH.balanceOf(alice);

            assertTrue(aliceUSDCBalance > 0, "Alice should have some USDC.");
            assertEq(aliceWETHBalance, 0, "Alice should have zero WETH.");
            assertEq(WBTC.balanceOf(alice), 0, "Alice should have zero WBTC.");
            assertEq(LINK.balanceOf(alice), 0, "Alice should have zero LINK.");

            assertApproxEqAbs(
                aliceUSDCBalance + priceRouter.getValue(WETH, aliceWETHBalance, USDC),
                expectedValue,
                0,
                "Alice's USDC and WETH worth should equal expectedValue."
            );
        }

        // Bob should only have USDC.
        {
            uint256 bobUSDCBalance = USDC.balanceOf(bob);
            uint256 bobWETHBalance = WETH.balanceOf(bob);

            assertTrue(bobUSDCBalance > 0, "Bob should have some USDC.");
            assertEq(bobWETHBalance, 0, "Bob should have zero WETH.");
            assertEq(WBTC.balanceOf(bob), 0, "Bob should have zero WBTC.");
            assertEq(LINK.balanceOf(bob), 0, "Bob should have zero LINK.");

            assertApproxEqAbs(bobUSDCBalance, expectedValue, 0, "Bob's USDC worth should equal expectedValue.");
        }

        //Sam should have WETH, and WBTC.
        {
            uint256 samUSDCBalance = USDC.balanceOf(sam);
            uint256 samWETHBalance = WETH.balanceOf(sam);
            uint256 samWBTCBalance = WBTC.balanceOf(sam);

            assertTrue(samUSDCBalance > 0, "Sam should have some USDC.");
            assertEq(samWETHBalance, 0, "Sam should have some WETH.");
            assertTrue(samWBTCBalance > 0, "Sam should have some WBTC.");
            assertEq(LINK.balanceOf(sam), 0, "Sam should have zero LINK.");

            assertApproxEqAbs(
                samUSDCBalance +
                    priceRouter.getValue(WETH, samWETHBalance, USDC) +
                    priceRouter.getValue(WBTC, samWBTCBalance, USDC),
                expectedValue,
                0,
                "Sam's USDC, WETH, and WBTC worth should equal expectedValue."
            );
        }

        //Mary should have USDC, and WBTC.
        {
            uint256 maryUSDCBalance = USDC.balanceOf(mary);
            uint256 maryWETHBalance = WETH.balanceOf(mary);
            uint256 maryWBTCBalance = WBTC.balanceOf(mary);

            assertEq(maryUSDCBalance, 0, "Mary should have zero USDC.");
            assertTrue(maryWETHBalance > 0, "Mary should have some WETH.");
            assertTrue(maryWBTCBalance > 0, "Mary should have some WBTC.");
            assertEq(LINK.balanceOf(mary), 0, "Mary should have zero LINK.");

            assertApproxEqAbs(
                maryUSDCBalance +
                    priceRouter.getValue(WETH, maryWETHBalance, USDC) +
                    priceRouter.getValue(WBTC, maryWBTCBalance, USDC),
                expectedValue,
                0,
                "Mary's USDC, WETH, and WBTC worth should equal expectedValue."
            );
        }
    }

    function testWETHAsCellarAsset(uint8 salt) external {
        // Initialize users.
        address alice = vm.addr(1);
        address bob = vm.addr(2);
        address sam = vm.addr(3);
        address mary = vm.addr(4);

        // Variable used to pass yield earned to _checkSendFees function.
        uint256 yieldEarned;

        // Initialize test Cellar.
        MockCellar assetManagementCellar;
        {
            // Add wBTC position to registry.
            uint32 wbtcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WBTC), 0, 0);

            // Create new cellar with WETH, USDC, and WBTC positions.
            uint32[] memory positions = new uint32[](3);
            positions[0] = wethPosition;
            positions[1] = usdcPosition;
            positions[2] = wbtcPosition;

            uint32[] memory debtPositions;

            bytes[] memory positionConfigs = new bytes[](3);

            bytes[] memory debtConfigs;

            assetManagementCellar = new MockCellar(
                registry,
                WETH,
                "Asset Management Cellar LP Token",
                "assetmanagement-CLR",
                abi.encode(positions, debtPositions, positionConfigs, debtConfigs, wethPosition, strategist)
            );
        }

        // Update allowed rebalance deviation to work with mock swap router.
        assetManagementCellar.setRebalanceDeviation(0.05e18);

        // Manipulate  test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore
            .target(address(assetManagementCellar))
            .sig(assetManagementCellar.shareLockPeriod.selector)
            .checked_write(uint256(0));

        assetManagementCellar.setupAdaptor(address(cellarAdaptor));

        // Give users WETH to interact with the Cellar.
        deal(address(WETH), alice, type(uint256).max);
        deal(address(WETH), bob, type(uint256).max);
        deal(address(WETH), sam, type(uint256).max);
        deal(address(WETH), mary, type(uint256).max);

        // Approve cellar to send user assets.
        vm.prank(alice);
        WETH.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(bob);
        WETH.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(sam);
        WETH.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(mary);
        WETH.approve(address(assetManagementCellar), type(uint256).max);

        // ====================== BEGIN SCENERIO ======================

        // Users join  cellar, cellar rebalances into USDC and WBTC positions,
        // and sendFees is called.
        {
            uint256 amount = (_mutate(salt) * 1e18) / 2000;
            uint256 shares;
            uint256 assets;

            // Alice joins cellar using deposit.
            (assets, shares) = _userAction(assetManagementCellar, alice, Action.DEPOSIT, amount, 0);
            assertEq(shares, assetManagementCellar.balanceOf(alice), "Alice should have got shares out from deposit.");

            // Bob joins cellar using Mint.
            uint256 bobAssets = WETH.balanceOf(bob);
            (assets, shares) = _userAction(assetManagementCellar, bob, Action.MINT, 0, shares);
            assertEq(
                assets,
                bobAssets - WETH.balanceOf(bob),
                "Bob should have `amount` of assets taken from his address."
            );

            // Sam joins cellar with deposit, withdraws half his assets, then adds them back in using mint.
            (assets, shares) = _userAction(assetManagementCellar, sam, Action.DEPOSIT, amount, 0);
            (assets, shares) = _userAction(assetManagementCellar, sam, Action.WITHDRAW, amount / 2, 0);
            (assets, shares) = _userAction(assetManagementCellar, sam, Action.MINT, 0, shares);
        }
        {
            // Strategy providers swaps into USDC and WBTC using WETH, targeting a 20/40/40 split(WETH/USDC/WBTC).
            uint256 totalAssets = assetManagementCellar.totalAssets();

            // Swap 40% of Cellars WETH for USDC.
            uint256 wethToSell = totalAssets.mulDivDown(4, 10);
            _rebalance(assetManagementCellar, WETH, USDC, wethToSell);

            // Swap 40% of Cellars WETH for WBTC.
            _rebalance(assetManagementCellar, WETH, WBTC, wethToSell);
        }
        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 7 days, USDC);
        _checkSendFees(assetManagementCellar, 7 days);

        // WBTC price increases enough to create yield, Mary joins the cellar, and sendFees is called.
        {
            uint256 totalAssets = assetManagementCellar.totalAssets();
            uint256 wBTCValueBefore = priceRouter.getValue(WBTC, WBTC.balanceOf(address(assetManagementCellar)), WETH);
            // WBTC price goes up.
            {
                ERC20[] memory assetsToAdjust = new ERC20[](3);
                uint256[] memory prices = new uint256[](3);
                assetsToAdjust[0] = USDC;
                assetsToAdjust[1] = WETH;
                assetsToAdjust[2] = WBTC;
                prices[0] = 1e8;
                prices[1] = 2_000e8;
                prices[2] = 45_000e8;
                _changeMarketPrices(assetsToAdjust, prices);
            }

            uint256 newTotalAssets = assetManagementCellar.totalAssets();

            uint256 wBTCValueAfter = priceRouter.getValue(WBTC, WBTC.balanceOf(address(assetManagementCellar)), WETH);

            yieldEarned = wBTCValueAfter - wBTCValueBefore;

            assertEq(
                newTotalAssets,
                (totalAssets + yieldEarned),
                "totalAssets after price increased by amount of yield earned."
            );
        }
        {
            uint256 amount = (_mutate(salt) * 1e18) / 2000;
            uint256 shares;
            uint256 assets;

            // Mary joins cellar using deposit.
            (assets, shares) = _userAction(assetManagementCellar, mary, Action.DEPOSIT, amount, 0);
        }

        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 0 days, USDC);
        _checkSendFees(assetManagementCellar, 7 days);

        // Adjust fee variables, lower WETH price but raise WBTC price enough to
        // create yield, rebalance all positions into WBTC, Bob and Sam join
        // cellar, and sendFees is called.
        {
            // Set platform fee to 2%.
            assetManagementCellar.setPlatformFee(0.02e18);

            // Set strategist platform cut to 80%.
            assetManagementCellar.setStrategistPlatformCut(0.8e18);

            // Strategist rebalances all positions to only WBTC
            uint256 assetBalanceToRemove = USDC.balanceOf(address(assetManagementCellar));
            _rebalance(assetManagementCellar, USDC, WBTC, assetBalanceToRemove);

            assetBalanceToRemove = WETH.balanceOf(address(assetManagementCellar));
            _rebalance(assetManagementCellar, WETH, WBTC, assetBalanceToRemove);

            // WETH price goes down. WBTC price goes up enough to create yield.
            {
                ERC20[] memory assetsToAdjust = new ERC20[](3);
                uint256[] memory prices = new uint256[](3);
                assetsToAdjust[0] = USDC;
                assetsToAdjust[1] = WETH;
                assetsToAdjust[2] = WBTC;
                prices[0] = 1e8;
                prices[1] = 1_500e8;
                prices[2] = 50_000e8;
                _changeMarketPrices(assetsToAdjust, prices);
            }
        }

        {
            // Bob enters cellar via `mint`.
            uint256 shares = (_mutate(salt) * 1e18) / 2000;

            deal(address(WETH), bob, type(uint256).max);
            (, shares) = _userAction(assetManagementCellar, bob, Action.MINT, 0, shares);
            deal(address(WETH), bob, 0);
            assetManagementCellar.balanceOf(address(assetManagementCellar));
            deal(address(WETH), sam, type(uint256).max);
            (, shares) = _userAction(assetManagementCellar, sam, Action.MINT, 0, shares);
            deal(address(WETH), sam, 0);

            _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 21 days, WBTC);
            _checkSendFees(assetManagementCellar, 21 days);
        }

        // No yield was earned, and 28 days pass.
        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 28 days, WBTC);
        _checkSendFees(assetManagementCellar, 28 days);

        // WBTC price decreases, rebalance cellar so that WETH in Cellar can not
        // cover Alice's redeem. Alice redeems shares, and call sendFees.
        {
            //===== Start Bear Market ====
            // WBTC price goes down.
            {
                ERC20[] memory assetsToAdjust = new ERC20[](3);
                uint256[] memory prices = new uint256[](3);
                assetsToAdjust[0] = USDC;
                assetsToAdjust[1] = WETH;
                assetsToAdjust[2] = WBTC;
                prices[0] = 1e8;
                prices[1] = 1_500e8;
                prices[2] = 30_000e8;
                _changeMarketPrices(assetsToAdjust, prices);
            }

            // Cellar has liquidity in WBTC and WETH, rebalance cellar so it
            // must take from USDC, and WETH position to cover Alice's redeem.
            uint256 shares = assetManagementCellar.balanceOf(alice);
            uint256 assets = assetManagementCellar.previewRedeem(shares);

            // Manually rebalance Cellar so that it only has 10% of assets needed for Alice's Redeem.
            {
                uint256 targetWETHBalance = assets / 10;
                uint256 currentWETHBalance = WETH.balanceOf(address(assetManagementCellar));
                uint256 totalAssets = assetManagementCellar.totalAssets();
                deal(address(WETH), address(assetManagementCellar), 0);
                if (targetWETHBalance > currentWETHBalance) {
                    // Need to move assets too WETH.
                    uint256 wbtcToRemove = priceRouter.getValue(WETH, (targetWETHBalance - currentWETHBalance), WBTC);
                    deal(
                        address(WBTC),
                        address(assetManagementCellar),
                        WBTC.balanceOf(address(assetManagementCellar)) - wbtcToRemove
                    );
                } else if (targetWETHBalance < currentWETHBalance) {
                    //Need to move assets from WETH.
                    uint256 wbtcToAdd = priceRouter.getValue(WETH, (currentWETHBalance - targetWETHBalance), WBTC);
                    deal(
                        address(WBTC),
                        address(assetManagementCellar),
                        WBTC.balanceOf(address(assetManagementCellar)) + wbtcToAdd
                    );
                }
                // Give cellar target WETH Balance such that total assets remains unchanged.
                deal(address(WETH), address(assetManagementCellar), totalAssets - assetManagementCellar.totalAssets());

                assertEq(
                    assetManagementCellar.totalAssets(),
                    totalAssets,
                    "Cellar total assets should not be changed."
                );
            }

            uint256 assetsForShares = assetManagementCellar.convertToAssets(shares);

            // Set Alice's WETH balance to zero to avoid overflow on transfer.
            deal(address(WETH), alice, 0);

            // Alice redeems her shares.
            (assets, shares) = _userAction(assetManagementCellar, alice, Action.REDEEM, 0, shares);
            assertEq(assetsForShares, assets, "Assets out should be worth assetsForShares.");
            assertTrue(WBTC.balanceOf(alice) > 0, "Alice should have gotten WBTC.");
            assertTrue(WETH.balanceOf(alice) > 0, "Alice should have gotten WETH.");
            assertEq(USDC.balanceOf(alice), 0, "Alice should not have gotten USDC.");
            uint256 WBTCworth = priceRouter.getValue(WBTC, WBTC.balanceOf(alice), WETH);
            assertApproxEqRel(
                WETH.balanceOf(alice) + WBTCworth,
                assets,
                0.00000001e18,
                "Value of assets out should approximately equal assets."
            );
        }

        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 7 days, WBTC);
        _checkSendFees(assetManagementCellar, 7 days);

        // Alice rejoins cellar, call sendFees.
        {
            // Alice rejoins via mint.
            uint256 sharesToMint = _mutate(salt) * 1e18;
            deal(address(WETH), alice, assetManagementCellar.previewMint(sharesToMint));
            _userAction(assetManagementCellar, alice, Action.MINT, 0, sharesToMint);
        }

        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 1 days, WBTC);
        _checkSendFees(assetManagementCellar, 1 days);

        // Rebalance cellar to move assets from WETH to WBTC.
        _rebalance(assetManagementCellar, WBTC, USDC, WBTC.balanceOf(address(assetManagementCellar)) / 2);

        {
            // WBTC goes up a little, USDC depeggs to 1.05.

            ERC20[] memory assetsToAdjust = new ERC20[](3);
            uint256[] memory prices = new uint256[](3);
            assetsToAdjust[0] = USDC;
            assetsToAdjust[1] = WETH;
            assetsToAdjust[2] = WBTC;
            prices[0] = 1.05e8;
            prices[1] = 1_000e8;
            prices[2] = 45_000e8;
            _changeMarketPrices(assetsToAdjust, prices);

            _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 14 days, WBTC);
            _checkSendFees(assetManagementCellar, 14 days);
        }
    }

    function testMultiAssetCellarWithIlliquidPositions(uint8 salt) external {
        // Initialize users.
        address alice = vm.addr(1);
        address bob = vm.addr(2);
        address sam = vm.addr(3);
        address mary = vm.addr(4);

        // Variable used to pass yield earned to _checkSendFees function.
        uint256 yieldEarned;

        // Initialize test Cellar.
        MockCellar assetManagementCellar;

        // Create two ERC4626 positions one with fully locked funds, and one with 90% of funds locked.
        LockedERC4626 lockedUSDC = new LockedERC4626(USDC, "Locked USDC", "LUSDC", 0.9e18); // 90% of funds are locked.
        LockedERC4626 lockedWETH = new LockedERC4626(WETH, "Locked WETH", "LWETH", 1e18); // 100% of funds are locked
        {
            // Create new cellar with WETH, USDC, and WBTC positions.
            uint32[] memory positions = new uint32[](4);
            positions[0] = wethPosition;
            positions[1] = registry.trustPosition(address(cellarAdaptor), abi.encode(lockedWETH), 0, 0);
            positions[2] = usdcPosition;
            positions[3] = registry.trustPosition(address(cellarAdaptor), abi.encode(lockedUSDC), 0, 0);

            uint32[] memory debtPositions;

            bytes[] memory positionConfigs = new bytes[](4);

            bytes[] memory debtConfigs;

            assetManagementCellar = new MockCellar(
                registry,
                WETH,
                "Asset Management Cellar LP Token",
                "assetmanagement-CLR",
                abi.encode(positions, debtPositions, positionConfigs, debtConfigs, wethPosition, strategist)
            );

            stdstore
                .target(address(assetManagementCellar))
                .sig(assetManagementCellar.shareLockPeriod.selector)
                .checked_write(uint256(0));
        }

        // Update allowed rebalance deviation to work with mock swap router.
        assetManagementCellar.setRebalanceDeviation(0.1e18);

        assetManagementCellar.setupAdaptor(address(cellarAdaptor));

        // Give users WETH to interact with the Cellar.
        deal(address(WETH), alice, type(uint256).max);
        deal(address(WETH), bob, type(uint256).max);
        deal(address(WETH), sam, type(uint256).max);
        deal(address(WETH), mary, type(uint256).max);

        // Approve cellar to send user assets.
        vm.prank(alice);
        WETH.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(bob);
        WETH.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(sam);
        WETH.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(mary);
        WETH.approve(address(assetManagementCellar), type(uint256).max);

        // ====================== BEGIN SCENERIO ======================

        // Users join  cellar, cellar rebalances into USDC and WBTC positions,
        // and sendFees is called.
        {
            uint256 amount = (_mutate(salt) * 1e18) / 2000;
            uint256 shares;
            uint256 assets;

            // Alice joins cellar using deposit.
            (assets, shares) = _userAction(assetManagementCellar, alice, Action.DEPOSIT, amount, 0);
            assertEq(shares, assetManagementCellar.balanceOf(alice), "Alice should have got shares out from deposit.");

            // Bob joins cellar using Mint.
            uint256 bobAssets = WETH.balanceOf(bob);
            (assets, shares) = _userAction(assetManagementCellar, bob, Action.MINT, 0, shares);
            assertEq(
                assets,
                bobAssets - WETH.balanceOf(bob),
                "Bob should have `amount` of assets taken from his address."
            );

            // Sam joins cellar with deposit, withdraws half his assets, then adds them back in using mint.
            (assets, shares) = _userAction(assetManagementCellar, sam, Action.DEPOSIT, amount, 0);
            (assets, shares) = _userAction(assetManagementCellar, sam, Action.WITHDRAW, amount / 2, 0);
            (assets, shares) = _userAction(assetManagementCellar, sam, Action.MINT, 0, shares);
        }
        {
            // Strategy providers swaps into USDC and WBTC using WETH, targeting a 20/40/40 split(WETH/USDC/WBTC).
            uint256 totalAssets = assetManagementCellar.totalAssets();

            // Swap 50% of Cellars WETH for USDC.
            uint256 wethToSell = totalAssets.mulDivDown(5, 10);
            _rebalance(assetManagementCellar, WETH, USDC, wethToSell);

            // Swap 40% of Cellars WETH for lockedWETH.
            wethToSell = totalAssets.mulDivDown(1, 10);
            _rebalanceWithERC4626Positions(assetManagementCellar, WETH, ERC20(address(lockedWETH)), wethToSell);

            // Move 80% of cellars  USDC into lockedUSDC.
            uint256 usdcBal = USDC.balanceOf(address(assetManagementCellar));
            _rebalanceWithERC4626Positions(
                assetManagementCellar,
                USDC,
                ERC20(address(lockedUSDC)),
                usdcBal.mulDivDown(4, 5)
            );
        }
        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 7 days, USDC);
        _checkSendFees(assetManagementCellar, 7 days);

        // WETH price decreases enough to create yield, Mary joins the cellar, and sendFees is called.
        {
            uint256 totalAssets = assetManagementCellar.totalAssets();
            // WETH price goes down.
            {
                ERC20[] memory assetsToAdjust = new ERC20[](2);
                uint256[] memory prices = new uint256[](2);
                assetsToAdjust[0] = USDC;
                assetsToAdjust[1] = WETH;
                prices[0] = 1e8;
                prices[1] = 1_500e8;
                _changeMarketPrices(assetsToAdjust, prices);
            }

            uint256 newTotalAssets = assetManagementCellar.totalAssets();

            yieldEarned = newTotalAssets - totalAssets;

            assertEq(
                newTotalAssets,
                (totalAssets + yieldEarned),
                "totalAssets after price increased by amount of yield earned."
            );
        }
        {
            uint256 amount = (_mutate(salt) * 1e18) / 2000;

            // Mary joins cellar using deposit.
            _userAction(assetManagementCellar, mary, Action.DEPOSIT, amount, 0);
        }

        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 0 days, USDC);
        _checkSendFees(assetManagementCellar, 7 days);

        // Adjust fee variables, lower WETH price but raise WBTC price enough to
        // create yield, Bob and Sam join
        // cellar, and sendFees is called.
        {
            // Set platform fee to 2%.
            assetManagementCellar.setPlatformFee(0.02e18);

            // Set strategist platform cut to 80%.
            assetManagementCellar.setStrategistPlatformCut(0.8e18);

            // WETH price goes down. USDC price goes down.
            {
                uint256 totalAssets = assetManagementCellar.totalAssets();
                ERC20[] memory assetsToAdjust = new ERC20[](2);
                uint256[] memory prices = new uint256[](2);
                assetsToAdjust[0] = USDC;
                assetsToAdjust[1] = WETH;
                prices[0] = 0.9998e8;
                prices[1] = 1_200e8;
                _changeMarketPrices(assetsToAdjust, prices);
                totalAssets = assetManagementCellar.totalAssets();
            }
        }

        {
            // Bob enters cellar via `mint`.
            uint256 shares = (_mutate(salt) * 1e18) / 2000;

            deal(address(WETH), bob, type(uint256).max);
            (, shares) = _userAction(assetManagementCellar, bob, Action.MINT, 0, shares);
            deal(address(WETH), bob, 0);
            assetManagementCellar.balanceOf(address(assetManagementCellar));
            deal(address(WETH), sam, type(uint256).max);
            (, shares) = _userAction(assetManagementCellar, sam, Action.MINT, 0, shares);
            deal(address(WETH), sam, 0);

            _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 21 days, USDC);
            _checkSendFees(assetManagementCellar, 21 days);
        }

        // No yield was earned, and 28 days pass.
        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 28 days, USDC);
        _checkSendFees(assetManagementCellar, 28 days);

        // Alice redeems shares, and call sendFees.
        {
            // Cellar has liquidity in USDC,  WETH, locked WETH, and lockedUSDC,
            // Alice withdraws as much as she can.
            uint256 assets = assetManagementCellar.maxWithdraw(alice);

            // Set Alice's WETH balance to zero to avoid overflow on transfer.
            deal(address(WETH), alice, 0);
            deal(address(USDC), alice, 0);
            // Alice redeems her shares.
            _userAction(assetManagementCellar, alice, Action.WITHDRAW, assets, 0);
            assertEq(USDC.balanceOf(alice), 0, "Alice should not have gotten USDC.");
            assertTrue(WETH.balanceOf(alice) > 0, "Alice should have gotten WETH.");
            assertApproxEqRel(
                WETH.balanceOf(alice),
                assets,
                0.00000001e18,
                "Value of assets out should approximately equal assets."
            );
        }

        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 7 days, USDC);
        _checkSendFees(assetManagementCellar, 7 days);

        // Alice rejoins cellar, call sendFees.
        {
            // Alice rejoins via mint.
            uint256 sharesToMint = _mutate(salt) * 1e18;
            deal(address(WETH), alice, assetManagementCellar.previewMint(sharesToMint));
            _userAction(assetManagementCellar, alice, Action.MINT, 0, sharesToMint);
        }

        _ensureEnoughAssetsToCoverSendFees(assetManagementCellar, 1 days, USDC);
        _checkSendFees(assetManagementCellar, 1 days);
        {
            // Everyone leaves  the cellar. Strategist must rebalance into liquid positions.
            uint256 assets = assetManagementCellar.maxWithdraw(bob);
            _userAction(assetManagementCellar, bob, Action.WITHDRAW, assets, 0);

            assets = assetManagementCellar.maxWithdraw(alice);
            _userAction(assetManagementCellar, alice, Action.WITHDRAW, assets, 0);

            assets = assetManagementCellar.maxWithdraw(mary);
            _userAction(assetManagementCellar, mary, Action.WITHDRAW, assets, 0);

            assets = assetManagementCellar.maxWithdraw(sam);
            _userAction(assetManagementCellar, sam, Action.WITHDRAW, assets, 0);

            // Strategist rebalances into liquid positions.
            _rebalanceWithERC4626Positions(
                assetManagementCellar,
                ERC20(address(lockedWETH)),
                WETH,
                WETH.balanceOf(address(lockedWETH))
            );
            _rebalanceWithERC4626Positions(
                assetManagementCellar,
                ERC20(address(lockedUSDC)),
                USDC,
                USDC.balanceOf(address(lockedUSDC))
            );

            // Have everyone completely exit the cellar.
            uint256 shares = assetManagementCellar.maxRedeem(bob);
            if (shares > 0) _userAction(assetManagementCellar, bob, Action.REDEEM, 0, shares);

            shares = assetManagementCellar.maxRedeem(alice);
            if (shares > 0) _userAction(assetManagementCellar, alice, Action.REDEEM, 0, shares);

            shares = assetManagementCellar.maxRedeem(mary);
            if (shares > 0) _userAction(assetManagementCellar, mary, Action.REDEEM, 0, shares);

            shares = assetManagementCellar.maxRedeem(sam);
            if (shares > 0) _userAction(assetManagementCellar, sam, Action.REDEEM, 0, shares);

            assertLt(assetManagementCellar.balanceOf(alice), 2, "alice should have no more shares.");
            assertLt(assetManagementCellar.balanceOf(bob), 2, "bob should have no more shares.");
            assertLt(assetManagementCellar.balanceOf(mary), 2, "mary should have no more shares.");
            assertLt(assetManagementCellar.balanceOf(sam), 2, "sam should have no more shares.");
        }
    }

    // ========================================= GRAVITY FUNCTIONS =========================================

    // Since this contract is set as the Gravity Bridge, this will be called by
    // the Cellar's `sendFees` function to send funds Cosmos.
    function sendToCosmos(
        address asset,
        bytes32,
        uint256 assets
    ) external {
        ERC20(asset).transferFrom(msg.sender, cosmos, assets);
    }
}
