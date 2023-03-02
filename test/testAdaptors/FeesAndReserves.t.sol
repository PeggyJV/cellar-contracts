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
        adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, 0, 0.2e4);
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
        FeesAndReserves.MetaData memory expectedMetaData = FeesAndReserves.MetaData({
            reserveAsset: USDC,
            managementFee: 0,
            timestamp: uint64(block.timestamp),
            reserves: 0,
            exactHighWatermark: 1e27,
            totalAssets: assets,
            feesOwed: 0,
            cellarDecimals: 18,
            reserveAssetDecimals: 6,
            performanceFee: 0.2e4
        });
        {
            FeesAndReserves.MetaData memory actualMetaData = far.getMetaData(cellar);

            assertEq(
                address(actualMetaData.reserveAsset),
                address(expectedMetaData.reserveAsset),
                "Reserve Asset should be USDC."
            );
            assertEq(actualMetaData.managementFee, expectedMetaData.managementFee, "Management fee should be 0.");
            assertEq(actualMetaData.timestamp, expectedMetaData.timestamp, "Timestamp should be block timestamp.");
            assertEq(actualMetaData.reserves, expectedMetaData.reserves, "Reserves should be zero.");
            assertEq(
                actualMetaData.exactHighWatermark,
                expectedMetaData.exactHighWatermark,
                "High Watermark should be 1 USDC."
            );
            assertEq(actualMetaData.totalAssets, expectedMetaData.totalAssets, "Total Assets should equal assets.");
            assertEq(actualMetaData.feesOwed, expectedMetaData.feesOwed, "There should be no performance fee owed.");
            assertEq(actualMetaData.cellarDecimals, expectedMetaData.cellarDecimals, "Cellar decimals should be 18.");
            assertEq(
                actualMetaData.reserveAssetDecimals,
                expectedMetaData.reserveAssetDecimals,
                "Reserve Asset decimals should be 6."
            );
            assertEq(actualMetaData.performanceFee, expectedMetaData.performanceFee, "Performance fee should be 20%.");
        }

        vm.warp(block.timestamp + 300);

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));

        assertEq(upkeepNeeded, false, "Upkeep should not be needed.");

        _simulateYieldAndCheckTotalFeesEarned(cellar, 1_000e6, 0);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

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
        adaptorCalls[0] = _createBytesDataToPrepareFees(far, metaData.feesOwed);
        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        (, , , uint256 reserves, , , uint256 feesOwed, , , ) = far.metaData(cellar);
        assertEq(reserves, amountOfUsdcToAddToReserves - metaData.feesOwed, "Reserves have been reduced.");
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

    function testPerformanceFees(uint256 totalAssets) external {
        totalAssets = bound(totalAssets, 100e6, 100_000_000e6);

        // Add assets to the cellar.
        deal(address(USDC), address(this), totalAssets);
        cellar.deposit(totalAssets, address(this));

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, uint32(0), 0.2e4);
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

        vm.warp(block.timestamp + 300);

        _simulateYieldAndCheckTotalFeesEarned(cellar, totalAssets.mulDivDown(1, 100), 0);
    }

    function testPerformanceFeeAccrual() external {
        uint256 totalAssets = 1_000_000e6;
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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, 0, 0.2e4);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 300);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        vm.warp(block.timestamp + 300);

        // Cellar earns yield.
        _simulateYieldAndCheckTotalFeesEarned(cellar, 100_000e6, 0);

        // Cellar loses yield.
        totalAssets = cellar.totalAssets();
        deal(address(USDC), address(cellar), totalAssets.mulDivDown(99, 100));
        _simulateYieldAndCheckTotalFeesEarned(cellar, 0, 0);

        // Pass in old perform data to try and take performance fees eventhough none are due.
        FeesAndReserves.MetaData memory oldMetaData = far.getMetaData(cellar);
        far.performUpkeep(performData);
        FeesAndReserves.MetaData memory newMetaData = far.getMetaData(cellar);

        // No new performance fees should be rewarded.
        assertApproxEqAbs(
            oldMetaData.feesOwed,
            newMetaData.feesOwed,
            1,
            "Actual Performance Fees differ from expected."
        );

        vm.warp(block.timestamp + 300);

        // Cellar regains lost yield, and performance fees are earned again.
        deal(address(USDC), address(cellar), totalAssets);

        _simulateYieldAndCheckTotalFeesEarned(cellar, 50_000e6, 0);
    }

    function testPerformUpkeepOnCellarNotSetUp() external {
        uint256 totalAssets = 1_000_000e6;
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

    // yield earned w performance fees
    function testYieldWithPerformanceFees() external {
        uint256 totalAssets = 1_000_000e6;
        uint256 yield = 200_000e6;
        uint32 performanceFee = 0.25e4;
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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, 0, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 0);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, 100 days);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = yield.mulDivDown(performanceFee, 1e4);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    // no yield earned w performance fees
    function testNoYieldWithPerformanceFees() external {
        uint256 totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, 0, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 0);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, 100 days);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = 0;

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    // Negative yield earned with performance fees.
    function testNegativeYieldWithPerformanceFees() external {
        uint256 totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, 0, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 0);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        deal(address(USDC), address(cellar), totalAssets.mulDivDown(99, 100));

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, 100 days);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = 0;

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    // yield earned w management fees
    function testManagementFees() external {
        uint256 totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0;
        uint32 managementFee = 0.02e4;
        uint256 timePassed = 100 days;

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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, managementFee, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 0);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, timePassed);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed, 365 days);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");

        // Have no time pass and immediately try earning management fees again.
        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, 0);

        metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should not change.");
    }

    // yield earned w both fees
    function testYieldWithPerformanceFeesAndManagementFees() external {
        uint256 totalAssets = 1_000_000e6;
        uint256 yield = 200_000e6;
        uint32 performanceFee = 0.25e4;
        uint32 managementFee = 0.02e4;
        uint256 timePassed = 100 days;

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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, managementFee, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 0);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, timePassed);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = yield.mulDivDown(performanceFee, 1e4);
        expectedFee += totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed, 365 days);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    // no yield earned w both fees
    function testNoYieldWithPerformanceFeesAndManagementFees() external {
        uint256 totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
        uint32 managementFee = 0.02e4;
        uint256 timePassed = 100 days;

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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, managementFee, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 0);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, 100 days);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = 0;
        expectedFee += totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed, 365 days);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    // Negative yield earned with both fees.
    function testNegativeYieldWithPerformanceFeesAndManagementFees() external {
        uint256 totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
        uint32 managementFee = 0.02e4;
        uint256 timePassed = 100 days;

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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(far, managementFee, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 0);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        totalAssets = totalAssets.mulDivDown(99, 100);
        deal(address(USDC), address(cellar), totalAssets);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, 100 days);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = 0;
        expectedFee += totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed, 365 days);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    function testFeesEarned(
        uint256 totalAssets,
        uint256 yield,
        uint256 timePassed,
        uint256 performanceFee,
        uint256 managementFee
    ) external {
        totalAssets = bound(totalAssets, 1e6, 1_000_000_000e6);
        yield = bound(yield, 0, 100_000_000_000e6);
        timePassed = bound(timePassed, 0, 150 days);
        performanceFee = bound(performanceFee, 0, 0.3e4);
        managementFee = bound(managementFee, 0, 0.1e4);

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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(
                far,
                uint32(managementFee),
                uint32(performanceFee)
            );
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(far, 1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(far, 300);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        vm.warp(block.timestamp + 300);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, timePassed);
    }

    function _simulateYieldAndCheckTotalFeesEarned(
        Cellar cellar,
        uint256 yield,
        uint256 timeToPass
    ) internal {
        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);
        // Save the current fees owed.
        uint256 currentFeesOwed = metaData.feesOwed;
        uint256 expectedFeesOwed;

        // Advance time.
        if (timeToPass > 0) vm.warp(block.timestamp + timeToPass);

        uint256 timeDelta = block.timestamp - metaData.timestamp;

        // Simulate yield.
        ERC20 asset = cellar.asset();
        deal(address(asset), address(cellar), asset.balanceOf(address(cellar)) + yield);

        uint256 minTotalAssets = cellar.totalAssets().min(metaData.totalAssets);

        // Calculate Share price normalized to 27 decimals.
        uint256 exactSharePrice = cellar.totalAssets().changeDecimals(metaData.reserveAssetDecimals, 27).mulDivDown(
            10**metaData.cellarDecimals,
            cellar.totalSupply()
        );

        if (metaData.managementFee > 0 && timeDelta > 0)
            expectedFeesOwed += minTotalAssets.mulDivDown(metaData.managementFee, 1e4).mulDivDown(timeDelta, 365 days);
        if (metaData.performanceFee > 0 && yield > 0) {
            expectedFeesOwed += minTotalAssets
                .mulDivDown(exactSharePrice - metaData.exactHighWatermark, 1e27)
                .mulDivDown(metaData.performanceFee, 1e4);
        }

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;

        (bool upkeepNeeded, bytes memory performData) = far.checkUpkeep(abi.encode(cellars));
        if (expectedFeesOwed > 0 || metaData.exactHighWatermark == 0) {
            assertEq(upkeepNeeded, true, "Upkeep should be needed!");
            far.performUpkeep(performData);
            metaData = far.getMetaData(cellar);
            uint256 newFeesOwed = metaData.feesOwed;
            assertApproxEqAbs((newFeesOwed - currentFeesOwed), expectedFeesOwed, 1, "Fees owed differs from expected.");
        } else assertEq(upkeepNeeded, false, "Upkeep should not be needed.");
    }

    // function _simulateYieldAndReturnExpectedAndPassTime(
    //     uint256 actualAPR,
    //     uint256 targetAPR,
    //     uint256 totalAssets,
    //     uint256 timeToPass
    // ) internal returns (uint256 expectedPerformanceFeeOwed) {
    //     // Determine yield earned.
    //     actualAPR = actualAPR.changeDecimals(4, 27);
    //     targetAPR = targetAPR.changeDecimals(4, 27);
    //     {
    //         uint256 expectedPercentIncrease = actualAPR.mulDivDown(timeToPass, 365 days);
    //         uint256 expectedYieldEarned = totalAssets.mulDivDown(expectedPercentIncrease, 1e27);
    //         // Simulate yield earned in Cellar.
    //         deal(address(USDC), address(cellar), totalAssets + expectedYieldEarned);
    //     }

    //     // Now calculate the expected performance fee owed.
    //     if (actualAPR >= targetAPR) {
    //         // Met/Exceeded target.
    //         expectedPerformanceFeeOwed = totalAssets.mulDivDown(targetAPR, 1e27).mulDivDown(0.2e4, 1e4).mulDivDown(
    //             timeToPass,
    //             365 days
    //         );
    //     } else {
    //         // Missed target.
    //         uint256 feeMultipler = 1e27 - (targetAPR - actualAPR).mulDivDown(1e27, targetAPR);
    //         expectedPerformanceFeeOwed = totalAssets
    //             .mulDivDown(actualAPR, 1e27)
    //             .mulDivDown(0.2e4, 1e4)
    //             .mulDivDown(timeToPass, 365 days)
    //             .mulDivDown(feeMultipler, 1e27);
    //     }

    //     // Advance Time.
    //     vm.warp(block.timestamp + timeToPass);
    // }

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

    function _createBytesDataToUpdateManagementFee(FeesAndReserves feesAndReserves, uint32 newFee)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.updateManagementFee.selector, feesAndReserves, newFee);
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
