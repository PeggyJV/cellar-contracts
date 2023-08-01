// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { FakeFeesAndReserves } from "src/mocks/FakeFeesAndReserves.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract FeesAndReservesTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    FeesAndReservesAdaptor private feesAndReservesAdaptor;
    Cellar private cellar;
    FeesAndReserves private far;

    uint32 private usdcPosition = 1;

    uint256 initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        far = new FeesAndReserves(address(this), automationRegistry, fastGasFeed);
        feesAndReservesAdaptor = new FeesAndReservesAdaptor(address(far));

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

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(feesAndReservesAdaptor));

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));

        string memory cellarName = "FeesAndReserves Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);

        cellar.setStrategistPayoutAddress(strategist);

        cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
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
            totalAssets: assets + initialAssets,
            feesOwed: 0,
            cellarDecimals: 6,
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
        data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCalls0 = new bytes[](1);
        adaptorCalls0[0] = _createBytesDataForSwapWithUniv3(WETH, USDC, 500, 1e18);
        data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls0 });

        bytes[] memory adaptorCalls1 = new bytes[](1);
        adaptorCalls1[0] = _createBytesDataToAddToReserves(amountOfUsdcToAddToReserves);
        data[1] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls1 });
        cellar.callOnAdaptor(data);

        data = new Cellar.AdaptorCall[](1);

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

    function testPerformanceFees(uint256 _totalAssets) external {
        _totalAssets = bound(_totalAssets, 100e6, 100_000_000e6);

        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

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

        _simulateYieldAndCheckTotalFeesEarned(cellar, _totalAssets.mulDivDown(1, 100), 0);
    }

    function testResetHWM() external {
        uint256 _totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

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

        deal(address(USDC), address(cellar), _totalAssets.mulDivDown(99, 100));

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

        uint256 _totalSupply = cellar.totalSupply();
        // Calculate Share price normalized to 27 decimals.
        uint256 currentSharePrice = cellar.totalAssets().changeDecimals(6, 27).mulDivDown(10 ** 6, _totalSupply);

        // Reset HWM halfway.
        uint256 expectedHWM = currentSharePrice + ((currentHWM - currentSharePrice) / 2);
        far.resetHWM(cellar, 0.5e4);

        metaData = far.getMetaData(cellar);

        assertApproxEqAbs(metaData.exactHighWatermark, expectedHWM, 1, "Stored HWM should equal expected.");

        // Make sure Cellars fees owed are reset.
        assertEq(metaData.feesOwed, 0, "Fees owed should have been reset.");

        // Now fully reset the HWM.
        far.resetHWM(cellar, 1e4);
        metaData = far.getMetaData(cellar);
        assertEq(metaData.exactHighWatermark, currentSharePrice, "Stored HWM should equal current share price.");
    }

    function testInvalidUpkeepFrequency() external {
        cellar.setRebalanceDeviation(0.05e18);
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist calls fees and reserves setup but uses an upkeep frequency that is too small.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](3);
        adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(0, 0.2e4);
        adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);
        adaptorCalls[2] = _createBytesDataToChangeUpkeepFrequency(600);

        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__MinimumUpkeepFrequencyNotMet.selector))
        );
        cellar.callOnAdaptor(data);

        // Strategist now tries to set everything but the upkeep frequency.
        adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataToSetupFeesAndReserves(0, 0.2e4);
        adaptorCalls[1] = _createBytesDataToChangeUpkeepMaxGas(1_000e9);

        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });

        // Call works, but checkUpkeep returns false, and performUpkeep reverts.
        cellar.callOnAdaptor(data);

        // Upkeep should not be needed.
        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = cellar;

        (bool upkeepNeeded, bytes memory performData) = far.checkUpkeep(abi.encode(cellars));

        assertEq(upkeepNeeded, false, "Upkeep should not be needed because frequency is not set.");

        // Try calling performUpkeep anyways.
        FeesAndReserves.PerformInput memory performInput;
        performInput.cellar = cellar;
        vm.expectRevert(bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__UpkeepTimeCheckFailed.selector)));
        far.performUpkeep(abi.encode(performInput));

        // Strategist properly sets frequency.
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToChangeUpkeepFrequency(1 days);

        data[0] = Cellar.AdaptorCall({ adaptor: address(feesAndReservesAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));

        assertEq(upkeepNeeded, true, "Upkeep should be needed to finish setup.");

        far.performUpkeep(performData);
    }

    function testPerformanceFeeAccrual() external {
        uint256 _totalAssets = 1_000_000e6;
        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

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
        _totalAssets = cellar.totalAssets();
        deal(address(USDC), address(cellar), _totalAssets.mulDivDown(99, 100));
        _simulateYieldAndCheckTotalFeesEarned(cellar, 0, 0);

        // Pass in old perform data to try and take performance fees eventhough none are due.
        vm.expectRevert(bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__UpkeepTimeCheckFailed.selector)));
        far.performUpkeep(performData);

        vm.warp(block.timestamp + 3_600);

        // Cellar regains lost yield, and performance fees are earned again.
        deal(address(USDC), address(cellar), _totalAssets);

        _simulateYieldAndCheckTotalFeesEarned(cellar, 50_000e6, 0);
    }

    function testPerformUpkeepOnCellarNotSetUp() external {
        uint256 _totalAssets = 1_000_000e6;
        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

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
        uint256 _totalAssets = 1_000_000e6;
        uint256 yield = 200_000e6;
        uint32 performanceFee = 0.25e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

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

        assertApproxEqAbs(metaData.feesOwed, expectedFee, 1, "Fees owed should equal expected.");
    }

    // no yield earned w performance fees
    function testNoYieldWithPerformanceFees() external {
        uint256 _totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

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
        uint256 _totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

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

        deal(address(USDC), address(cellar), _totalAssets.mulDivDown(99, 100));

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, 100 days);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = 0;

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    // yield earned w management fees
    function testManagementFees() external {
        uint256 _totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0;
        uint32 managementFee = 0.02e4;
        uint256 timePassed = 100 days;

        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

        _totalAssets = cellar.totalAssets();

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
        uint256 expectedFee = _totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed, 365 days);

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

        expectedFee += _totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed / 2, 365 days);

        metaData = far.getMetaData(cellar);

        assertEq(metaData.timestamp, block.timestamp, "Stored timestamp should equal current time.");
        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    // yield earned w both fees
    function testYieldWithPerformanceFeesAndManagementFees() external {
        uint256 _totalAssets = 1_000_000e6;
        uint256 yield = 200_000e6;
        uint32 performanceFee = 0.25e4;
        uint32 managementFee = 0.02e4;
        uint256 timePassed = 100 days;

        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

        _totalAssets = cellar.totalAssets();

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
        expectedFee += _totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed, 365 days);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertApproxEqAbs(metaData.feesOwed, expectedFee, 1, "Fees owed should equal expected.");
    }

    // no yield earned w both fees
    function testNoYieldWithPerformanceFeesAndManagementFees() external {
        uint256 _totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
        uint32 managementFee = 0.02e4;
        uint256 timePassed = 100 days;

        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

        _totalAssets = cellar.totalAssets();

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
        expectedFee += _totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed, 365 days);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    // Negative yield earned with both fees.
    function testNegativeYieldWithPerformanceFeesAndManagementFees() external {
        uint256 _totalAssets = 1_000_000e6;
        uint256 yield = 0;
        uint32 performanceFee = 0.25e4;
        uint32 managementFee = 0.02e4;
        uint256 timePassed = 100 days;

        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

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

        _totalAssets = _totalAssets.mulDivDown(99, 100);
        deal(address(USDC), address(cellar), _totalAssets);

        _simulateYieldAndCheckTotalFeesEarned(cellar, yield, 100 days);

        // Management fees are zero, so cellar should only earn yield * performance fee.
        uint256 expectedFee = 0;
        expectedFee += _totalAssets.mulDivDown(managementFee, 1e4).mulDivDown(timePassed, 365 days);

        FeesAndReserves.MetaData memory metaData = far.getMetaData(cellar);

        assertEq(metaData.feesOwed, expectedFee, "Fees owed should equal expected.");
    }

    function testFeesEarned(
        uint256 _totalAssets,
        uint256 yield,
        uint256 timePassed,
        uint256 performanceFee,
        uint256 managementFee
    ) external {
        _totalAssets = bound(_totalAssets, 1e6, 1_000_000_000e6);
        yield = bound(yield, 0, 100_000_000_000e6);
        timePassed = bound(timePassed, 0, 150 days);
        performanceFee = bound(performanceFee, 0, 0.3e4);
        managementFee = bound(managementFee, 0, 0.1e4);

        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

        _totalAssets = cellar.totalAssets();

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
        Cellar cellarA = _createFARCellar("1");
        Cellar cellarB = _createFARCellar("2");
        Cellar cellarC = _createFARCellar("3");

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
        uint256 _totalAssets = 1_000_000e6;
        uint256 yield = 200_000e6;
        uint32 performanceFee = 0.25e4;
        // Add assets to the cellar.
        deal(address(USDC), address(this), _totalAssets);
        cellar.deposit(_totalAssets, address(this));

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

    // ========================================= Malicious Caller Test =========================================

    // Values used to mimic cellar interface between test contract and FeesAndReserves.
    ERC20 public asset;
    uint8 public decimals = 18;
    uint256 public totalAssets;
    uint256 public totalSupply;

    function feeData()
        public
        view
        returns (uint64 strategistPlatformCut, uint64 platformFee, uint64 lastAccrual, address strategistPayoutAddress)
    {
        return (0.8e18, 0, 0, strategist);
    }

    function testMaliciousCallerChangingReserveAsset() external {
        // Set this testing contracts `asset` to be USDC.
        asset = USDC;

        far.setupMetaData(0.05e4, 0.2e4);
        far.changeUpkeepMaxGas(100e9);
        far.changeUpkeepFrequency(3_600);

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = Cellar(address(this));
        totalAssets = 100e18;
        totalSupply = 100e18;
        (bool upkeepNeeded, bytes memory performData) = far.checkUpkeep(abi.encode(cellars));
        far.performUpkeep(performData);

        vm.warp(block.timestamp + 3_600);

        // Add assets to reserves.
        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(far), 100e6);
        far.addAssetsToReserves(100e6);

        // Change asset to WETH.
        asset = WETH;

        // Try removing assets to take WETH from FeesAndReserves.
        far.withdrawAssetsFromReserves(100e6);

        assertEq(WETH.balanceOf(address(this)), 0, "Test contract should have no WETH.");
        assertEq(USDC.balanceOf(address(this)), 100e6, "Test contract should have original USDC balance.");

        // Withdrawing more assets should revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__NotEnoughReserves.selector)));
        far.withdrawAssetsFromReserves(1);

        // Adjust totalAssets so that far thinks there are performance fees owed.
        totalAssets = 200e18;
        vm.warp(block.timestamp + 365 days);

        (upkeepNeeded, performData) = far.checkUpkeep(abi.encode(cellars));
        assertEq(upkeepNeeded, true, "Upkeep should be needed.");
        far.performUpkeep(performData);

        // Add some assets to reserves.
        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(far), 100e6);
        far.addAssetsToReserves(100e6);

        // Prepare fees.
        far.prepareFees(1e6);

        far.sendFees(Cellar(address(this)));

        // Strategist should have recieved USDC.
        assertGt(USDC.balanceOf(strategist), 0, "Strategist should have got USDC from performance fees.");

        // Even though caller maliciously changed their `asset`, FeesAndReserves did not use the new asset, it used the asset stored when `setupMetaData` was called.
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _createFARCellar(string memory cellarName) internal returns (Cellar target) {
        // Setup Cellar:

        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        target = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);

        target.addAdaptorToCatalogue(address(feesAndReservesAdaptor));

        USDC.safeApprove(address(target), type(uint256).max);

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
        ERC20 yieldAsset = target.asset();
        deal(address(yieldAsset), address(target), yieldAsset.balanceOf(address(target)) + yield);

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

    // ========================================= GRAVITY FUNCTIONS =========================================

    // Since this contract is set as the Gravity Bridge, this will be called by
    // the Cellar's `sendFees` function to send funds Cosmos.
    function sendToCosmos(address assetToSend, bytes32, uint256 assets) external {
        ERC20(assetToSend).transferFrom(msg.sender, cosmos, assets);
    }
}
