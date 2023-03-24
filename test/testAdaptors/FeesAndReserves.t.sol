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
import { FakeFeesAndReserves } from "src/mocks/FakeFeesAndReserves.sol";
import { MockFeesAndReservesAdaptor } from "src/mocks/adaptors/MockFeesAndReservesAdaptor.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract FeesAndReservesTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MockFeesAndReservesAdaptor private feesAndReservesAdaptor;
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
        feesAndReservesAdaptor = new MockFeesAndReservesAdaptor();
        erc20Adaptor = new ERC20Adaptor();
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        registry = new Registry(address(this), address(swapRouter), address(priceRouter));
        far = new FeesAndReserves(registry);

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
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(feesAndReservesAdaptor));

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));

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

        cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));

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
        adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(0, 0.2e4);
        adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
        adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

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

        vm.warp(block.timestamp + 3_600);

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
        adaptorCalls[1] = _createBytesDataToAddToReserves(amountOfUsdcToAddToReserves);

        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Strategist calls prepareFees.
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToPrepareFees(metaData.feesOwed);
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
        adaptorCalls[0] = _createBytesDataToWithdrawFromReserves(reserves);
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
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(uint32(0), 0.2e4);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

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

        vm.warp(block.timestamp + 3_600);

        _simulateYieldAndCheckTotalFeesEarned(cellar, totalAssets.mulDivDown(1, 100), 0);
    }

    function testResetHWM() external {
        uint256 totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), totalAssets);
        cellar.deposit(totalAssets, address(this));

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(0, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

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

        // Owner of fees and reserves tries resetting cellars HWM with illogical percents.
        vm.expectRevert(bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__InvalidResetPercent.selector)));
        far.resetHWM(cellar, 0);

        // Owner of fees and reserves tries resetting cellars HWM with illogical percents.
        vm.expectRevert(bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__InvalidResetPercent.selector)));
        far.resetHWM(cellar, 1.0001e4);

        uint256 currentHWM = metaData.exactHighWatermark;

        uint256 totalSupply = cellar.totalSupply();
        // Calculate Share price normalized to 27 decimals.
        uint256 currentSharePrice = cellar.totalAssets().changeDecimals(6, 27).mulDivDown(10 ** 18, totalSupply);

        // Reset HWM halfway.
        uint256 expectedHWM = currentSharePrice + ((currentHWM - currentSharePrice) / 2);
        far.resetHWM(cellar, 0.5e4);

        metaData = far.getMetaData(cellar);

        assertEq(metaData.exactHighWatermark, expectedHWM, "Stored HWM should equal expected.");

        // Make sure Cellars fees owed are reset.
        assertEq(metaData.feesOwed, 0, "Fees owed should have been reset.");

        // Now fully reset the HWM.
        far.resetHWM(cellar, 1e4);
        metaData = far.getMetaData(cellar);
        assertEq(metaData.exactHighWatermark, currentSharePrice, "Stored HWM should equal current share price.");
    }

    function testPerformanceFeeAccrual() external {
        uint256 totalAssets = 1_000_000e6;
        // Add assets to the cellar.
        deal(address(USDC), address(this), totalAssets);
        cellar.deposit(totalAssets, address(this));

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(0, 0.2e4);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        vm.warp(block.timestamp + 3_600);

        // Cellar earns yield.
        _simulateYieldAndCheckTotalFeesEarned(cellar, 100_000e6, 0);

        // Cellar loses yield.
        totalAssets = cellar.totalAssets();
        deal(address(USDC), address(cellar), totalAssets.mulDivDown(99, 100));
        _simulateYieldAndCheckTotalFeesEarned(cellar, 0, 0);

        // Pass in old perform data to try and take performance fees eventhough none are due.
        vm.expectRevert(bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__UpkeepTimeCheckFailed.selector)));
        far.performUpkeep(performData);

        vm.warp(block.timestamp + 3_600);

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
        bytes memory performData;

        FeesAndReserves.PerformInput[] memory inputs = new FeesAndReserves.PerformInput[](1);
        inputs[0].cellar = cellar;

        performData = abi.encode(inputs);

        vm.expectRevert(bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__CellarNotSetup.selector)));
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
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(0, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

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
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(0, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

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
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(0, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

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
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(managementFee, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, timePassed);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed, 365 days);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        uint256 expectedTime = block.timestamp;
        assertEq(metaData.timestamp, expectedTime, "Stored timestamp should equal expectedTime.");
        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");

        // Have no time pass and immediately try earning management fees again.
        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, 0);

        metaData = far.getMetaData(cellar);

        assertEq(metaData.timestamp, expectedTime, "Stored timestamp should equal expectedTime.");
        assertEq(metaData.feesOwed, expectedFee, "Fees owed should not change.");

        // Pass the some more time and make sure that management fee is still right.
        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, timePassed / 2);

        expectedFee += totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed / 2, 365 days);

        metaData = far.getMetaData(cellar);

        assertEq(metaData.timestamp, block.timestamp, "Stored timestamp should equal current time.");
        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
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
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(managementFee, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

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
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(managementFee, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

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
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(managementFee, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

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
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(uint32(managementFee), uint32(performanceFee));
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        vm.warp(block.timestamp + 3_600);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, timePassed);
    }

    function testMultipleCellarsServedByOneUpkeep() external {
        Cellar cellarA = _createCellar();
        Cellar cellarB = _createCellar();
        Cellar cellarC = _createCellar();

        Cellar[] memory cellars = new Cellar[](3);
        cellars[0] = cellarA;
        cellars[1] = cellarB;
        cellars[2] = cellarC;
        bytes memory performData;
        bool upkeepNeeded;
        FeesAndReserves.PerformInput memory input;
        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));

        // Warp so enough time has passed to allow upkeeps.
        vm.warp(block.timestamp + 3_600);

        assertEq(upkeepNeeded, false, "Upkeep should not be needed.");

        //Simulate yield on Cellars, A, B, C.
        uint256 yield = 1_000e6;
        deal(address(USDC), address(cellarA), USDC.balanceOf(address(cellarA)) + yield);
        deal(address(USDC), address(cellarB), USDC.balanceOf(address(cellarB)) + yield);
        deal(address(USDC), address(cellarC), USDC.balanceOf(address(cellarC)) + yield);

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));
        input = abi.decode(performData, (FeesAndReserves.PerformInput));
        assertEq(upkeepNeeded, true, "Upkeep should be needed.");
        assertEq(address(input.cellar), address(cellarA), "Cellar A should need upkeep.");
        far.performUpkeep(performData);

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));
        input = abi.decode(performData, (FeesAndReserves.PerformInput));
        assertEq(upkeepNeeded, true, "Upkeep should be needed.");
        assertEq(address(input.cellar), address(cellarB), "Cellar B should need upkeep.");
        far.performUpkeep(performData);

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));
        input = abi.decode(performData, (FeesAndReserves.PerformInput));
        assertEq(upkeepNeeded, true, "Upkeep should be needed.");
        assertEq(address(input.cellar), address(cellarC), "Cellar C should need upkeep.");
        far.performUpkeep(performData);

        // Warp so enough time has passed to allow upkeeps.
        vm.warp(block.timestamp + 3_600);

        // Yield is only earned on cellar A, and C
        deal(address(USDC), address(cellarA), USDC.balanceOf(address(cellarA)) + yield);
        deal(address(USDC), address(cellarC), USDC.balanceOf(address(cellarC)) + yield);

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));
        input = abi.decode(performData, (FeesAndReserves.PerformInput));
        assertEq(upkeepNeeded, true, "Upkeep should be needed.");
        assertEq(address(input.cellar), address(cellarA), "Cellar A should need upkeep.");
        far.performUpkeep(performData);

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));
        input = abi.decode(performData, (FeesAndReserves.PerformInput));
        assertEq(upkeepNeeded, true, "Upkeep should be needed.");
        assertEq(address(input.cellar), address(cellarC), "Cellar C should need upkeep.");
        far.performUpkeep(performData);
    }

    function testStalePerformData() external {
        uint256 totalAssets = 1_000_000e6;
        uint256 yield = 200_000e6;
        uint32 performanceFee = 0.25e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), totalAssets);
        cellar.deposit(totalAssets, address(this));

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(0, performanceFee);
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        // Warp so enough time has passed to allow upkeeps.
        vm.warp(block.timestamp + 3_600);

        // Give cellar some yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + yield);

        (, performData) = far.checkUpkeep(abi.encode(cellars));

        // Some time passes.
        vm.warp(block.timestamp + 3_600);

        // EOA manually calls performUpkeep, while keeper TX is stuck.
        far.performUpkeep(performData);

        // Enough time has passed to allow for another upkeep, but keeper tries to submit stale inputs.
        vm.warp(block.timestamp + 3_600);

        // Prank automation registry address.
        vm.startPrank(0x02777053d6764996e594c3E88AF1D58D5363a2e6);
        vm.expectRevert(bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__UpkeepTimeCheckFailed.selector)));
        far.performUpkeep(performData);
        vm.stopPrank();
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _createCellar() internal returns (Cellar target) {
        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](1);
        uint32[] memory debtPositions;

        positions[0] = usdcPosition;

        bytes[] memory positionConfigs = new bytes[](1);
        bytes[] memory debtConfigs;

        target = new Cellar(
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

        target.addAdaptorToCatalogue(address(feesAndReservesAdaptor));

        USDC.safeApprove(address(target), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(target)).sig(target.shareLockPeriod.selector).checked_write(uint256(0));

        // Add assets to the cellar.
        deal(address(USDC), address(this), 100_000e6);
        target.deposit(100_000e6, address(this));

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = target;
        bytes memory performData;

        // Strategist calls fees and reserves setup.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(uint32(0), uint32(0.2e4));
            adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
            adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(3_600);

            data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
            target.callOnAdaptor(data);
        }

        (, performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);
    }

    function _simulateYieldAndCheckTotalFeesEarned(Cellar target, uint256 yield, uint256 timeToPass) internal {
        FeesAndReserves.MetaData memory targetMetaData = far.getMetaData(target);
        // Save the current fees owed.
        uint256 currentFeesOwed = targetMetaData.feesOwed;
        uint256 expectedFeesOwed;

        // Advance time.
        if (timeToPass > 0) vm.warp(block.timestamp + timeToPass);

        uint256 timeDelta = block.timestamp - targetMetaData.timestamp;

        // Simulate yield.
        ERC20 asset = target.asset();
        deal(address(asset), address(target), asset.balanceOf(address(target)) + yield);

        uint256 minTotalAssets = target.totalAssets().min(targetMetaData.totalAssets);

        // Calculate Share price normalized to 27 decimals.
        uint256 exactSharePrice = target
            .totalAssets()
            .changeDecimals(targetMetaData.reserveAssetDecimals, 27)
            .mulDivDown(10 ** targetMetaData.cellarDecimals, target.totalSupply());

        if (targetMetaData.managementFee > 0 && timeDelta > 0)
            expectedFeesOwed += minTotalAssets.mulDivDown(targetMetaData.managementFee, 1e4).mulDivDown(
                timeDelta,
                365 days
            );
        if (targetMetaData.performanceFee > 0 && yield > 0) {
            expectedFeesOwed += minTotalAssets
                .mulDivDown(exactSharePrice - targetMetaData.exactHighWatermark, 1e27)
                .mulDivDown(targetMetaData.performanceFee, 1e4);
        }

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = target;

        (bool upkeepNeeded, bytes memory performData) = far.checkUpkeep(abi.encode(cellars));
        if (expectedFeesOwed > 0 || targetMetaData.exactHighWatermark == 0) {
            assertEq(upkeepNeeded, true, "Upkeep should be needed!");
            far.performUpkeep(performData);
            targetMetaData = far.getMetaData(target);
            uint256 newFeesOwed = targetMetaData.feesOwed;
            assertApproxEqAbs((newFeesOwed - currentFeesOwed), expectedFeesOwed, 1, "Fees owed differs from expected.");
        } else assertEq(upkeepNeeded, false, "Upkeep should not be needed.");
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
        uint32 targetAPR,
        uint32 performanceFee
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.setupMetaData.selector, targetAPR, performanceFee);
    }

    function _createBytesDataToChangeUpkeepFrequency(uint64 newFrequency) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.changeUpkeepFrequency.selector, newFrequency);
    }

    function _createBytesDataToChangeUpkeepMaxGas(uint64 newMaxGas) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.changeUpkeepMaxGas.selector, newMaxGas);
    }

    function _createBytesDataToAddToReserves(uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.addAssetsToReserves.selector, amount);
    }

    function _createBytesDataToWithdrawFromReserves(uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.withdrawAssetsFromReserves.selector, amount);
    }

    function _createBytesDataToPrepareFees(uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.prepareFees.selector, amount);
    }

    function _createBytesDataToUpdateManagementFee(uint32 newFee) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.updateManagementFee.selector, newFee);
    }

    // ========================================= GRAVITY FUNCTIONS =========================================

    // Since this contract is set as the Gravity Bridge, this will be called by
    // the Cellar's `sendFees` function to send funds Cosmos.
    function sendToCosmos(address asset, bytes32, uint256 assets) external {
        ERC20(asset).transferFrom(msg.sender, cosmos, assets);
    }
}
