// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract FeesAndReservesTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    FeesAndReservesAdaptor private feesAndReservesAdaptor;
    ERC20Adaptor private erc20Adaptor;
    Cellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;
    FeesAndReserves private far;

    address private immutable strategist = vm.addr(0xBEEF);
    address private immutable cosmos = vm.addr(0xCAAA);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    // Note this is the BTC USD data feed, but we assume the risk that WBTC depegs from BTC.
    address private WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address private TUSD_USD_FEED = 0xec746eCF986E2927Abd291a2A1716c940100f8Ba;

    uint32 private usdcPosition;

    function setUp() external {
        feesAndReservesAdaptor = new FeesAndReservesAdaptor();
        erc20Adaptor = new ERC20Adaptor();
        priceRouter = new PriceRouter();
        far = new FeesAndReserves();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage({
            max: 0,
            min: 0,
            heartbeat: 170 days,
            inETH: false
        });

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](1);
        uint32[] memory debtPositions;

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);
        registry.trustAdaptor(address(feesAndReservesAdaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC), 0, 0);

        positions[0] = usdcPosition;

        bytes[] memory positionConfigs = new bytes[](1);
        bytes[] memory debtConfigs;

        cellar = new Cellar(
            registry,
            USDC,
            "FAR Cellar",
            "FAR-CLR",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                usdcPosition,
                strategist,
                type(uint128).max,
                type(uint128).max
            )
        );

        cellar.setupAdaptor(address(feesAndReservesAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testPositiveYield() external {
        cellar.setRebalanceDeviation(0.05e18);
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist calls fees and reserves setup.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](3);
        adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, 0.05e4, 0.2e4);
        adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
        adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 300);

        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Upkeep should be needed.
        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;

        (bool upkeepNeeded, bytes memory performData) = far.checkUpkeep(abi.encode(cellars));

        assertTrue(upkeepNeeded, "Upkeep should be needed to finish setup.");

        far.performUpkeep(performData);
        {
            (
                ERC20 reserveAsset,
                uint32 targetAPR,
                ,
                ,
                // uint64 timestamp,
                // uint256 reserves,
                uint256 highWaterMark,
                uint256 totalAssets,
                uint256 performanceFeesOwed, // uint8 cellarDecimals, // uint8 reserveAssetDecimals, // uint32 performanceFee
                ,
                ,

            ) = far.metaData(cellar);

            assertEq(address(reserveAsset), address(USDC), "Reserve Asset should be USDC.");
            assertEq(targetAPR, 0.05e4, "Target APR should be 5%.");
            // assertEq(timestamp, block.timestamp, "Timestamp should be block timestamp.");
            // assertEq(reserves, 0, "Reserves should be zero.");
            assertEq(highWaterMark, 1e27, "High Watermark should be 1 USDC.");
            assertEq(totalAssets, assets, "Total Assets should equal assets.");
            assertEq(performanceFeesOwed, 0, "There should be no performance fee owed.");
            // assertEq(cellarDecimals, 18, "Cellar decimals should be 18.");
            // assertEq(reserveAssetDecimals, 6, "Reserve Asset decimals should be 6.");
            // assertEq(performanceFee, 0.2e4, "Performance fee should be 20%.");
        }

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));

        assertEq(upkeepNeeded, false, "Upkeep should not be needed.");

        uint256 expectedPerformanceFees = _simulateYieldAndReturnExpectedAndPassTime(
            0.05e4,
            0.05e4,
            cellar.totalAssets(),
            600
        );

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));

        assertEq(upkeepNeeded, true, "Upkeep should be needed because there is yield.");

        far.performUpkeep(performData);

        {
            (, , , , uint256 highWaterMark, , uint256 performanceFeesOwed, , , ) = far.metaData(cellar);
            assertApproxEqAbs(
                performanceFeesOwed,
                expectedPerformanceFees,
                1,
                "Performance fees owed should be 20% of yield earned."
            );
        }

        expectedPerformanceFees += _simulateYieldAndReturnExpectedAndPassTime(
            0.05e4,
            0.05e4,
            cellar.totalAssets(),
            10 days
        );

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));

        assertEq(upkeepNeeded, true, "Upkeep should be needed because there is yield.");

        far.performUpkeep(performData);

        uint256 performanceFeesOwed;
        {
            (, , , , , , performanceFeesOwed, , , ) = far.metaData(cellar);
            assertEq(
                performanceFeesOwed,
                expectedPerformanceFees,
                "Performance fees owed should be 20% of yield earned."
            );
        }

        // Now give the cellar yield in an untracked asset WETH, so that it can be added to reserves.
        deal(address(WETH), address(cellar), 1e18);

        uint256 amountOfUsdcToAddToReserves = priceRouter.getValue(WETH, 1e18, USDC).mulDivDown(99, 100);

        // Leave expected yield in contract so that strategist earns full performance fees.
        // Strategist swaps WETH yield into USDC, then adds it to reserves.
        adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(WETH, USDC, 500, 1e18);
        adaptorCalls[1] = _createBytesDataToAddToReserves(far, amountOfUsdcToAddToReserves);

        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Strategist calls prepareFees.
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToPrepareFees(far, performanceFeesOwed);
        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        (, , , uint256 reserves, , , uint256 feesOwed, , , ) = far.metaData(cellar);
        assertEq(reserves, amountOfUsdcToAddToReserves - performanceFeesOwed, "Reserves have been reduced.");
        assertEq(feesOwed, 0, "feesOwed should be zero.");

        far.sendFees(cellar);

        assertEq(far.feesReadyForClaim(cellar), 0, "Fees ready for claim should be zero.");

        assertTrue(USDC.balanceOf(strategist) > 0, "Strategist should have earned USDC fees.");

        uint256 expectedTotalAssets = cellar.totalAssets() + reserves;

        // Strategist withdraws some assets from reserves.
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToWithdrawFromReserves(far, reserves);
        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        (, , , reserves, , , , , , ) = far.metaData(cellar);

        assertEq(reserves, 0, "Reserves should be zero.");

        assertEq(cellar.totalAssets(), expectedTotalAssets, "Total assets should have increased by `reserves` amount.");
    }

    function testPerformanceFees(
        uint256 targetAPR,
        uint256 actualAPR,
        uint256 totalAssets,
        uint256 timeToPass
    ) external {
        targetAPR = bound(targetAPR, 0.01e4, 100e4);
        actualAPR = bound(actualAPR, 0, 100e4);
        totalAssets = bound(totalAssets, 100e6, 100_000_000e6);
        timeToPass = bound(timeToPass, 300, 100 days);

        // Add assets to the cellar.
        deal(address(USDC), address(this), totalAssets);
        cellar.deposit(totalAssets, address(this));

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, uint32(targetAPR), 0.2e4);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 300);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        // Upkeep should be needed.
        {
            Cellar[] memory cellars = new Cellar[](1);
            cellars[0] = cellar;

            (, bytes memory performData) = far.checkUpkeep(abi.encode(cellars));

            far.performUpkeep(performData);
        }

        // Determine Expected Performance Fees Owed.
        uint256 expectedPerformanceFeeOwed = _simulateYieldAndReturnExpectedAndPassTime(
            actualAPR,
            targetAPR,
            totalAssets,
            timeToPass
        );

        // Upkeep should be needed, but can be false if above bounds are small enough, so return if no upkeep is needed.
        {
            Cellar[] memory cellars = new Cellar[](1);
            cellars[0] = cellar;

            (bool upkeepNeeded, bytes memory performData) = far.checkUpkeep(abi.encode(cellars));
            if (!upkeepNeeded) return;

            far.performUpkeep(performData);
        }

        (, , , , , , uint256 performanceFeesOwed, , , ) = far.metaData(cellar);
        assertApproxEqAbs(
            performanceFeesOwed,
            expectedPerformanceFeeOwed,
            1,
            "Performance fees owed should be 20% of yield earned."
        );
    }

    function testPerformanceFeeAccrual() external {
        uint256 totalAssets = 1_000_000e6;
        uint32 targetAPR = 0.05e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), totalAssets);
        cellar.deposit(totalAssets, address(this));

        uint256 performanceFeesOwed;
        uint256 actualPerformanceFeesOwed;
        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;
        bool upkeepNeeded;
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, targetAPR, 0.2e4);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 300);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        // Cellar earns yield.
        performanceFeesOwed = _simulateYieldAndReturnExpectedAndPassTime(0.03e4, targetAPR, totalAssets, 10 days);

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        (, , , , , , actualPerformanceFeesOwed, , , ) = far.metaData(cellar);

        assertApproxEqAbs(
            actualPerformanceFeesOwed,
            performanceFeesOwed,
            1,
            "Actual Performance Fees differ from expected."
        );

        totalAssets = cellar.totalAssets();

        // Cellar loses yield.
        deal(address(USDC), address(cellar), totalAssets.mulDivDown(99, 100));
        (upkeepNeeded, ) = far.checkUpkeep(abi.encode(cellars));
        assertEq(upkeepNeeded, false, "Upkeep should not be needed.");
        // Pass in old perform data to try and take performance fees eventhough none are due.
        far.performUpkeep(performData);
        // No new performance fees should be rewarded.
        (, , , , , , actualPerformanceFeesOwed, , , ) = far.metaData(cellar);
        assertApproxEqAbs(
            actualPerformanceFeesOwed,
            performanceFeesOwed,
            1,
            "Actual Performance Fees differ from expected."
        );

        // Cellar regains lost yield, and performance fees are earned again.
        deal(address(USDC), address(cellar), totalAssets);

        performanceFeesOwed += _simulateYieldAndReturnExpectedAndPassTime(0.04e4, targetAPR, totalAssets, 20 days);
        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        (, , , , , , actualPerformanceFeesOwed, , , ) = far.metaData(cellar);

        assertApproxEqAbs(
            actualPerformanceFeesOwed,
            performanceFeesOwed,
            1,
            "Actual Performance Fees differ from expected."
        );
    }

    function testOverPerformingCellarUpdatingVsNotUpdating() external {
        uint256 totalAssets = 1_000_000e6;
        uint32 targetAPR = 0.05e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), totalAssets);
        cellar.deposit(totalAssets, address(this));

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;
        bool upkeepNeeded;
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, targetAPR, 0.2e4);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 300);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        uint256 performanceFeesEarnedWithoutUpdatingTarget;
        performanceFeesEarnedWithoutUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        performanceFeesEarnedWithoutUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        performanceFeesEarnedWithoutUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        performanceFeesEarnedWithoutUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        performanceFeesEarnedWithoutUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);

        (, , , , , , performanceFeesEarnedWithoutUpdatingTarget, , , ) = far.metaData(cellar);

        console.log("Total Fees Earned No Updating", performanceFeesEarnedWithoutUpdatingTarget);

        // Reset Cellars yield.
        deal(address(USDC), address(cellar), totalAssets);
        far.resetHWM(cellar);

        // Run same calculations with a cellar
        uint256 performanceFeesEarnedWithUpdatingTarget;
        _updateTargetAPR(cellar, 0.06e4);
        performanceFeesEarnedWithUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        targetAPR = 0.06e4;
        _updateTargetAPR(cellar, 0.07e4);
        performanceFeesEarnedWithUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        targetAPR = 0.07e4;
        _updateTargetAPR(cellar, 0.08e4);
        performanceFeesEarnedWithUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        targetAPR = 0.08e4;
        _updateTargetAPR(cellar, 0.09e4);
        performanceFeesEarnedWithUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        targetAPR = 0.09e4;
        _updateTargetAPR(cellar, 0.1e4);
        performanceFeesEarnedWithUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.1e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        targetAPR = 0.1e4;

        (, , , , , , performanceFeesEarnedWithUpdatingTarget, , , ) = far.metaData(cellar);
        performanceFeesEarnedWithUpdatingTarget =
            performanceFeesEarnedWithUpdatingTarget -
            performanceFeesEarnedWithoutUpdatingTarget;

        console.log("Total Fees Earned Updating", performanceFeesEarnedWithUpdatingTarget);

        // Reset Cellars yield.
        deal(address(USDC), address(cellar), totalAssets);
        far.resetHWM(cellar);

        // Now run same test, but where Cellar target is perfect.
        uint256 maxPossibleFees;
        maxPossibleFees += _simulateYieldAndReturnExpectedAndPassTime(0.1e4, targetAPR, cellar.totalAssets(), 10 days);
        far.performUpkeep(performData);
        maxPossibleFees += _simulateYieldAndReturnExpectedAndPassTime(0.1e4, targetAPR, cellar.totalAssets(), 10 days);
        far.performUpkeep(performData);
        maxPossibleFees += _simulateYieldAndReturnExpectedAndPassTime(0.1e4, targetAPR, cellar.totalAssets(), 10 days);
        far.performUpkeep(performData);
        maxPossibleFees += _simulateYieldAndReturnExpectedAndPassTime(0.1e4, targetAPR, cellar.totalAssets(), 10 days);
        far.performUpkeep(performData);
        maxPossibleFees += _simulateYieldAndReturnExpectedAndPassTime(0.1e4, targetAPR, cellar.totalAssets(), 10 days);
        far.performUpkeep(performData);

        (, , , , , , maxPossibleFees, , , ) = far.metaData(cellar);
        maxPossibleFees =
            maxPossibleFees -
            (performanceFeesEarnedWithUpdatingTarget + performanceFeesEarnedWithoutUpdatingTarget);

        console.log("Max Possible Fees", maxPossibleFees);

        assertGt(
            maxPossibleFees,
            performanceFeesEarnedWithUpdatingTarget,
            "Cellar with accurate target should earn more fees."
        );
        assertGt(
            performanceFeesEarnedWithUpdatingTarget,
            performanceFeesEarnedWithoutUpdatingTarget,
            "Upadting target should earn more fees."
        );
    }

    function testUnderPerformingCellarUpdatingVsNotUpdating() external {
        uint256 totalAssets = 1_000_000e6;
        uint32 targetAPR = 0.05e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), totalAssets);
        cellar.deposit(totalAssets, address(this));

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;
        bool upkeepNeeded;
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, targetAPR, 0.2e4);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 300);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        uint256 performanceFeesEarnedWithoutUpdatingTarget;
        performanceFeesEarnedWithoutUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.01e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        performanceFeesEarnedWithoutUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.01e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        performanceFeesEarnedWithoutUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.01e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        performanceFeesEarnedWithoutUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.01e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);

        (, , , , , , performanceFeesEarnedWithoutUpdatingTarget, , , ) = far.metaData(cellar);

        console.log("Total Fees Earned No Updating", performanceFeesEarnedWithoutUpdatingTarget);

        // Reset Cellars yield.
        deal(address(USDC), address(cellar), totalAssets);
        far.resetHWM(cellar);

        // Run same calculations with a cellar
        uint256 performanceFeesEarnedWithUpdatingTarget;
        _updateTargetAPR(cellar, 0.04e4);
        performanceFeesEarnedWithUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.01e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        targetAPR = 0.04e4;
        _updateTargetAPR(cellar, 0.03e4);
        performanceFeesEarnedWithUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.01e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        targetAPR = 0.03e4;
        _updateTargetAPR(cellar, 0.02e4);
        performanceFeesEarnedWithUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.01e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        targetAPR = 0.02e4;
        _updateTargetAPR(cellar, 0.01e4);
        performanceFeesEarnedWithUpdatingTarget += _simulateYieldAndReturnExpectedAndPassTime(
            0.01e4,
            targetAPR,
            cellar.totalAssets(),
            10 days
        );
        far.performUpkeep(performData);
        targetAPR = 0.01e4;

        (, , , , , , performanceFeesEarnedWithUpdatingTarget, , , ) = far.metaData(cellar);
        performanceFeesEarnedWithUpdatingTarget =
            performanceFeesEarnedWithUpdatingTarget -
            performanceFeesEarnedWithoutUpdatingTarget;

        console.log("Total Fees Earned Updating", performanceFeesEarnedWithUpdatingTarget);

        // Reset Cellars yield.
        deal(address(USDC), address(cellar), totalAssets);
        far.resetHWM(cellar);

        // Now run same test, but where Cellar target is perfect.
        uint256 maxPossibleFees;
        maxPossibleFees += _simulateYieldAndReturnExpectedAndPassTime(0.01e4, targetAPR, cellar.totalAssets(), 10 days);
        far.performUpkeep(performData);
        maxPossibleFees += _simulateYieldAndReturnExpectedAndPassTime(0.01e4, targetAPR, cellar.totalAssets(), 10 days);
        far.performUpkeep(performData);
        maxPossibleFees += _simulateYieldAndReturnExpectedAndPassTime(0.01e4, targetAPR, cellar.totalAssets(), 10 days);
        far.performUpkeep(performData);
        maxPossibleFees += _simulateYieldAndReturnExpectedAndPassTime(0.01e4, targetAPR, cellar.totalAssets(), 10 days);
        far.performUpkeep(performData);

        (, , , , , , maxPossibleFees, , , ) = far.metaData(cellar);
        maxPossibleFees =
            maxPossibleFees -
            (performanceFeesEarnedWithUpdatingTarget + performanceFeesEarnedWithoutUpdatingTarget);

        console.log("Max Possible Fees", maxPossibleFees);

        assertGt(
            maxPossibleFees,
            performanceFeesEarnedWithUpdatingTarget,
            "Cellar with accurate target should earn more fees."
        );
        assertGt(
            performanceFeesEarnedWithUpdatingTarget,
            performanceFeesEarnedWithoutUpdatingTarget,
            "Upadting target should earn more fees."
        );
    }

    function testPerformUpkeepOnCellarNotSetUp() external {
        uint256 totalAssets = 1_000_000e6;
        uint32 targetAPR = 0.05e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), totalAssets);
        cellar.deposit(totalAssets, address(this));

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;
        bool upkeepNeeded;
        bytes memory performData;

        FeesAndReserves.PerformInput[] memory inputs = new FeesAndReserves.PerformInput[](1);
        inputs[0].cellar = cellar;

        performData = abi.encode(inputs);

        vm.expectRevert(bytes("Cellar not setup."));
        far.performUpkeep(performData);
    }

    function _updateTargetAPR(Cellar cellar, uint32 newTarget) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToUpdateTargetAPR(far, newTarget);
        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _simulateYieldAndReturnExpectedAndPassTime(
        uint256 actualAPR,
        uint256 targetAPR,
        uint256 totalAssets,
        uint256 timeToPass
    ) internal returns (uint256 expectedPerformanceFeeOwed) {
        // Determine yield earned.
        actualAPR = actualAPR.changeDecimals(4, 27);
        targetAPR = targetAPR.changeDecimals(4, 27);
        {
            uint256 expectedPercentIncrease = actualAPR.mulDivDown(timeToPass, 365 days);
            uint256 expectedYieldEarned = totalAssets.mulDivDown(expectedPercentIncrease, 1e27);
            // Simulate yield earned in Cellar.
            deal(address(USDC), address(cellar), totalAssets + expectedYieldEarned);
        }

        // Now calculate the expected performance fee owed.
        if (actualAPR >= targetAPR) {
            // Met/Exceeded target.
            expectedPerformanceFeeOwed = totalAssets.mulDivDown(targetAPR, 1e27).mulDivDown(0.2e4, 1e4).mulDivDown(
                timeToPass,
                365 days
            );
        } else {
            // Missed target.
            uint256 feeMultipler = 1e27 - (targetAPR - actualAPR).mulDivDown(1e27, targetAPR);
            expectedPerformanceFeeOwed = totalAssets
                .mulDivDown(actualAPR, 1e27)
                .mulDivDown(0.2e4, 1e4)
                .mulDivDown(timeToPass, 365 days)
                .mulDivDown(feeMultipler, 1e27);
        }

        // Advance Time.
        vm.warp(block.timestamp + timeToPass);
    }

    function _createBytesDataForSwap(
        ERC20 from,
        ERC20 to,
        uint24 poolFee,
        uint256 fromAmount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = poolFee;
        bytes memory params = abi.encode(path, poolFees, fromAmount, 0);
        return
            abi.encodeWithSelector(BaseAdaptor.swap.selector, from, to, fromAmount, SwapRouter.Exchange.UNIV3, params);
    }

    // Make sure that if a strategists makes a huge deposit before calling log fees, it doesn't affect fee pay out
    function _createBytesDataToSetupFeesAndReserves(
        FeesAndReserves feesAndReserves,
        uint32 targetAPR,
        uint32 performanceFee
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                FeesAndReservesAdaptor.setupMetaData.selector,
                feesAndReserves,
                targetAPR,
                performanceFee
            );
    }

    function _createBytesDataToChangeUpkeepFrequency(FeesAndReserves feesAndReserves, uint64 newFrequency)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodeWithSelector(
                FeesAndReservesAdaptor.changeUpkeepFrequency.selector,
                feesAndReserves,
                newFrequency
            );
    }

    function _createBytesDataToChangeUpkeepMaxGas(FeesAndReserves feesAndReserves, uint64 newMaxGas)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.changeUpkeepMaxGas.selector, feesAndReserves, newMaxGas);
    }

    function _createBytesDataToAddToReserves(FeesAndReserves feesAndReserves, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.addAssetsToReserves.selector, feesAndReserves, amount);
    }

    function _createBytesDataToWithdrawFromReserves(FeesAndReserves feesAndReserves, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodeWithSelector(FeesAndReservesAdaptor.withdrawAssetsFromReserves.selector, feesAndReserves, amount);
    }

    function _createBytesDataToPrepareFees(FeesAndReserves feesAndReserves, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.prepareFees.selector, feesAndReserves, amount);
    }

    function _createBytesDataToUpdateTargetAPR(FeesAndReserves feesAndReserves, uint32 newTarget)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.updateTargetAPR.selector, feesAndReserves, newTarget);
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
