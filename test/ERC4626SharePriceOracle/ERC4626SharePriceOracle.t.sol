// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { ERC4626SharePriceOracle, IRegistry, IRegistrar } from "src/base/ERC4626SharePriceOracle.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract ERC4626SharePriceOracleTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    AaveATokenAdaptor private aaveATokenAdaptor;
    MockDataFeed private usdcMockFeed;
    MockDataFeed private wethMockFeed;
    Cellar private cellar;
    ERC4626SharePriceOracle private sharePriceOracle;

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    uint32 private usdcPosition = 1;
    uint32 private aV2USDCPosition = 2;
    uint32 private debtUSDCPosition = 3;
    uint32 private wethPosition = 4;

    uint256 private initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18364794;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        usdcMockFeed = new MockDataFeed(USDC_USD_FEED);
        wethMockFeed = new MockDataFeed(WETH_USD_FEED);
        aaveATokenAdaptor = new AaveATokenAdaptor(address(pool), address(WETH), 1.05e18);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(address(wethMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(wethMockFeed));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(usdcMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(usdcMockFeed));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(aaveATokenAdaptor));

        registry.trustPosition(aV2USDCPosition, address(aaveATokenAdaptor), abi.encode(address(aV2USDC)));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(address(USDC)));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(address(WETH)));

        uint256 minHealthFactor = 1.1e18;

        string memory cellarName = "Simple Aave Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(
            cellarName,
            USDC,
            aV2USDCPosition,
            abi.encode(minHealthFactor),
            initialDeposit,
            platformCut
        );

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));

        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPosition(1, usdcPosition, abi.encode(true), false);

        USDC.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();

        ERC4626 _target = ERC4626(address(cellar));
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0005e4;
        uint64 _gracePeriod = 60 * 60; // 1 hr
        uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
        address _automationRegistry = automationRegistryV2;
        address _automationRegistrar = automationRegistrarV2;
        address _automationAdmin = address(this);

        // Setup share price oracle.
        ERC4626SharePriceOracle.ConstructorArgs memory args = ERC4626SharePriceOracle.ConstructorArgs(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            _automationRegistrar,
            _automationAdmin,
            address(LINK),
            1e18,
            0.01e4,
            10e4,
            address(0),
            0
        );
        sharePriceOracle = new ERC4626SharePriceOracle(args);

        uint96 initialUpkeepFunds = 10e18;
        deal(address(LINK), address(this), initialUpkeepFunds);
        LINK.safeApprove(address(sharePriceOracle), initialUpkeepFunds);
        sharePriceOracle.initialize(initialUpkeepFunds);

        // Write storage to change forwarder to address this.
        stdstore.target(address(sharePriceOracle)).sig(sharePriceOracle.automationForwarder.selector).checked_write(
            address(this)
        );
    }

    function testHappyPath() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            aV2USDC.balanceOf(address(cellar)),
            assets + initialAssets,
            1,
            "Assets should have been deposited into Aave."
        );

        bool upkeepNeeded;
        bytes memory performData;
        // uint256 checkGas = gasleft();
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        // console.log("Gas used for checkUpkeep", checkGas - gasleft());
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        // uint256 performGas = gasleft();
        sharePriceOracle.performUpkeep(performData);
        // console.log("Gas Used for PerformUpkeep", performGas - gasleft());
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(!upkeepNeeded, "Upkeep should not be needed.");

        vm.warp(block.timestamp + 1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        vm.warp(block.timestamp + 1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        vm.warp(block.timestamp + 1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        vm.warp(block.timestamp + 1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        // Advance time to 1 sec after grace period, and make sure we revert when trying to get TWAA,
        // until enough observations are added that this delayed entry is no longer affecting TWAA.
        bool checkNotSafeToUse;
        vm.warp(block.timestamp + 1 days + 3601);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        vm.warp(block.timestamp + 1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        vm.warp(block.timestamp + 1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        vm.warp(block.timestamp + 1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        uint256 currentSharePrice = cellar.previewRedeem(1e6);

        // Get time weighted average share price.
        // uint256 gas = gasleft();
        (uint256 ans, uint256 timeWeightedAverageAnswer, bool notSafeToUse) = sharePriceOracle.getLatest();
        ans = ans.changeDecimals(18, 6);
        timeWeightedAverageAnswer = timeWeightedAverageAnswer.changeDecimals(18, 6);
        // console.log("Gas Used For getLatest", gas - gasleft());
        assertTrue(!notSafeToUse, "Should be safe to use");
        assertEq(ans, currentSharePrice, "Answer should be equal to current share price.");
        assertGt(currentSharePrice, timeWeightedAverageAnswer, "Current share price should be greater than TWASP.");
    }

    function testGetLatestPositiveYield() external {
        cellar.setHoldingPosition(usdcPosition);
        // Test latestAnswer over a 3 day period.
        uint64 dayOneYield = 1.001e4;
        uint64 dayTwoYield = 1.0005e4;
        uint64 dayThreeYield = 1.0005e4;
        bool checkNotSafeToUse;
        uint256 answer;
        uint256 twaa;

        // Have user deposit into cellar.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 1, "Index should be 1");

        _passTimeAlterSharePriceAndUpkeep(1 days, dayOneYield);
        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 2, "Index should be 2");

        // Simulate deviation from share price triggers an update.
        _passTimeAlterSharePriceAndUpkeep(43_200, dayOneYield);
        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 2, "Index should be 2");

        // 12 hrs later, the timeDeltaSincePreviousObservation check should trigger an update.
        _passTimeAlterSharePriceAndUpkeep(43_200, dayTwoYield);
        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 3, "Index should be 3");

        _passTimeAlterSharePriceAndUpkeep(1 days, dayThreeYield);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 4, "Index should be 4");

        assertGt(answer, twaa, "Answer should be larger than TWAA since all yield was positive.");
    }

    function testGetLatestNegativeYield() external {
        cellar.setHoldingPosition(usdcPosition);
        // Test latestAnswer over a 3 day period.
        uint64 dayOneYield = 0.990e4;
        uint64 dayTwoYield = 0.9995e4;
        uint64 dayThreeYield = 0.9993e4;
        bool checkNotSafeToUse;
        uint256 answer;
        uint256 twaa;

        // Have user deposit into cellar.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 1, "Index should be 1");

        _passTimeAlterSharePriceAndUpkeep(1 days, dayOneYield);
        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 2, "Index should be 2");

        // Simulate deviation from share price triggers an update.
        _passTimeAlterSharePriceAndUpkeep(43_200, dayOneYield);
        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 2, "Index should be 2");

        // 12 hrs later, the timeDeltaSincePreviousObservation check should trigger an update.
        _passTimeAlterSharePriceAndUpkeep(43_200, dayTwoYield);
        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 3, "Index should be 3");

        _passTimeAlterSharePriceAndUpkeep(1 days, dayThreeYield);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");

        assertEq(sharePriceOracle.currentIndex(), 4, "Index should be 4");

        assertGt(twaa, answer, "TWASS should be larger than answer since all yield was negative.");
    }

    function testStrategistForgetsToFillUpkeep(uint256 forgetTime) external {
        forgetTime = bound(forgetTime, 1, 3 days);
        cellar.setHoldingPosition(usdcPosition);
        bool checkNotSafeToUse;
        uint256 answer;
        uint256 twaa;

        // Have user deposit into cellar.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        // Log TWAA details for 3 days, so that answer is usable.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");

        // Upkeep becomes underfunded, and strategist forgets to fill it.
        _passTimeAlterSharePriceAndUpkeep(1 days + 3_600 + forgetTime, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        // Strategist refills upkeep with link and pricing can continue as normal once observations are written.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");
    }

    function testSuppressedUpkeepAttack(uint256 suppressionTime) external {
        suppressionTime = bound(suppressionTime, 1, 3 days);
        cellar.setHoldingPosition(usdcPosition);
        bool checkNotSafeToUse;
        uint256 answer;
        uint256 twaa;

        // Have user deposit into cellar.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        // Log TWAA details for 3 days, so that answer is usable.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");

        vm.warp(block.timestamp + 1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);

        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");

        // Attacker allows upkeep to go through.
        sharePriceOracle.performUpkeep(performData);

        // Another day passes.
        vm.warp(block.timestamp + 1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);

        // Upkeep is needed, but attacker starts suppressing chainlink upkeeps.
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");

        // Attacker suppresses updates for heartbest + grace period + suppressionTime.
        vm.warp(block.timestamp + 1 days + 3_600 + suppressionTime);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);

        // Attacker finally allows upkeep to succeed.
        sharePriceOracle.performUpkeep(performData);

        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        // Must wait unitl observations are filled up with fresh data before we can start pricing again.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);

        // Finally have enough observations so value is safe to use.
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");
    }

    function testSharePriceManipulationAttack(uint256 suppressionTime) external {
        suppressionTime = bound(suppressionTime, 1, 3 days);
        cellar.setHoldingPosition(usdcPosition);
        bool checkNotSafeToUse;
        uint256 answer;
        uint256 twaa;

        // Have user deposit into cellar.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        // Log TWAA details for 3 days, so that answer is usable.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");

        (uint256 answerBeforeAttack, uint256 twaaBeforeAttack, ) = sharePriceOracle.getLatest();

        // Assume an attack found some way to alter the target Cellar share price temporarily.
        // Attacker raises share price 10x, right before observation is complete.
        _passTimeAlterSharePriceAndUpkeep(1 days, 10e4);

        (answer, , ) = sharePriceOracle.getLatest();

        assertApproxEqRel(answer, 10 * answerBeforeAttack, 0.01e18, "Oracle answer should have been 10xed from attack");

        // Attacker is able to hold share price at 10x for 10 min.
        vm.warp(block.timestamp + 600);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);

        // Attacker returns share price to what it was before attack.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(0.1e4, 1e4));

        // Upkeep should be needed due to deviation.
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();

        // TWAA calculation includes 3 days of good values, and 10 min of attacker bad values.
        assertApproxEqRel(
            twaa,
            twaaBeforeAttack,
            0.021e18,
            "Attack should have little effect on time weighted average share price."
        );

        // Also check that once this observations ends and we use the next one that TWAA is good as well.
        // Worst case scenario because total TWAP is 3 days, but inludes the 10 min
        // where attacker had elevated share price.
        _passTimeAlterSharePriceAndUpkeep(1 days - 600, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");

        assertApproxEqRel(
            twaa,
            twaaBeforeAttack,
            0.021e18,
            "Attack should have little effect on time weighted average share price."
        );
    }

    function testGracePeriod(uint256 delayOne, uint256 delayTwo, uint256 delayThree) external {
        cellar.setHoldingPosition(usdcPosition);

        uint256 gracePeriod = sharePriceOracle.gracePeriod();

        delayOne = bound(delayOne, 0, gracePeriod);
        delayTwo = bound(delayTwo, 0, gracePeriod - delayOne);
        delayThree = bound(delayThree, 0, gracePeriod - (delayOne + delayTwo));

        // Have user deposit into cellar.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        _passTimeAlterSharePriceAndUpkeep(1 days + delayOne, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days + delayTwo, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days + delayThree, 1e4);

        (, , bool checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");

        // But if the next reading is delayed 1 more second than gracePeriod - (delayTwo + delayThree), pricing is not safe to use.
        uint256 unsafeDelay = 1 + (gracePeriod - (delayTwo + delayThree));
        _passTimeAlterSharePriceAndUpkeep(1 days + unsafeDelay, 1e4);

        (, , checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");
    }

    function testOracleUpdatesFromDeviation() external {
        cellar.setHoldingPosition(usdcPosition);

        // Have user deposit into cellar.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        // Update share price so that it falls under the update deviation.
        vm.warp(block.timestamp + 600);

        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(!upkeepNeeded, "Upkeep should not be needed.");

        uint256 sharePriceMultiplier = 0.9994e4;
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier, 1e4));

        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        assertEq(sharePriceOracle.currentIndex(), 1, "Index should be 1");

        // Update share price so that it falls over the update deviation.
        vm.warp(block.timestamp + 600);

        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(!upkeepNeeded, "Upkeep should not be needed.");

        sharePriceMultiplier = 1.0006e4;
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier, 1e4));

        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        assertEq(sharePriceOracle.currentIndex(), 1, "Index should be 1");
    }

    function testTimeWeightedAverageAnswerWithDeviationUpdates(
        uint256 assets,
        uint256 sharePriceMultiplier0,
        uint256 sharePriceMultiplier1
    ) external {
        // Rebalance aV2USDC into USDC position.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2(USDC, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
            // Perform callOnAdaptor.
            cellar.callOnAdaptor(data);
        }

        cellar.setHoldingPosition(usdcPosition);
        sharePriceMultiplier0 = bound(sharePriceMultiplier0, 0.7e4, 0.94e4);
        sharePriceMultiplier1 = bound(sharePriceMultiplier1, 1.06e4, 1.5e4);
        uint256 sharePriceMultiplier2 = sharePriceMultiplier0 / 2;
        uint256 sharePriceMultiplier3 = sharePriceMultiplier0 / 3;
        uint256 sharePriceMultiplier4 = sharePriceMultiplier0 / 4;
        uint256 sharePriceMultiplier5 = (sharePriceMultiplier1 * 1.1e4) / 1e4;
        uint256 sharePriceMultiplier6 = (sharePriceMultiplier1 * 1.2e4) / 1e4;
        uint256 sharePriceMultiplier7 = (sharePriceMultiplier1 * 1.3e4) / 1e4;
        sharePriceMultiplier0 = sharePriceMultiplier0 < 1e4 ? sharePriceMultiplier0 - 6 : sharePriceMultiplier0 + 6;
        sharePriceMultiplier1 = sharePriceMultiplier1 < 1e4 ? sharePriceMultiplier1 - 6 : sharePriceMultiplier1 + 6;
        sharePriceMultiplier2 = sharePriceMultiplier2 < 1e4 ? sharePriceMultiplier2 - 6 : sharePriceMultiplier2 + 6;
        sharePriceMultiplier3 = sharePriceMultiplier3 < 1e4 ? sharePriceMultiplier3 - 6 : sharePriceMultiplier3 + 6;
        sharePriceMultiplier4 = sharePriceMultiplier4 < 1e4 ? sharePriceMultiplier4 - 6 : sharePriceMultiplier4 + 6;
        sharePriceMultiplier5 = sharePriceMultiplier5 < 1e4 ? sharePriceMultiplier5 - 6 : sharePriceMultiplier5 + 6;
        sharePriceMultiplier6 = sharePriceMultiplier6 < 1e4 ? sharePriceMultiplier6 - 6 : sharePriceMultiplier6 + 6;
        sharePriceMultiplier7 = sharePriceMultiplier7 < 1e4 ? sharePriceMultiplier7 - 6 : sharePriceMultiplier7 + 6;

        // Have user deposit into cellar.
        assets = bound(assets, 0.1e6, 1_000_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        assertEq(sharePriceOracle.currentIndex(), 1, "Wrong Current Index");

        uint256 startingCumulative = _calcCumulative(cellar, 0, (block.timestamp - 1));
        uint256 cumulative = startingCumulative;

        // Deviate outside threshold for first 12 hours
        vm.warp(block.timestamp + (1 days / 2));
        cumulative = _calcCumulative(cellar, cumulative, (1 days / 2));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier0, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        assertEq(sharePriceOracle.currentIndex(), 1, "Wrong Current Index");

        // For last 12 hours, reset to original share price.
        cumulative = _calcCumulative(cellar, cumulative, (1 days / 2));
        _passTimeAlterSharePriceAndUpkeep((1 days / 2), sharePriceMultiplier1);

        assertEq(sharePriceOracle.currentIndex(), 2, "Wrong Current Index");

        // Deviate outside threshold for first 6 hours
        vm.warp(block.timestamp + (1 days / 4));
        cumulative = _calcCumulative(cellar, cumulative, (1 days / 4));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier2, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        assertEq(sharePriceOracle.currentIndex(), 2, "Wrong Current Index");

        // Deviate outside threshold for first 6-12 hours
        vm.warp(block.timestamp + (1 days / 4));
        cumulative = _calcCumulative(cellar, cumulative, (1 days / 4));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier3, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        assertEq(sharePriceOracle.currentIndex(), 2, "Wrong Current Index");

        // Deviate outside threshold for 12-18 hours
        vm.warp(block.timestamp + (1 days / 4));
        cumulative = _calcCumulative(cellar, cumulative, (1 days / 4));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier4, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        assertEq(sharePriceOracle.currentIndex(), 2, "Wrong Current Index");

        // For last 6 hours show a loss.
        cumulative = _calcCumulative(cellar, cumulative, (1 days / 4));
        _passTimeAlterSharePriceAndUpkeep((1 days / 4), sharePriceMultiplier5);

        assertEq(sharePriceOracle.currentIndex(), 3, "Wrong Current Index");

        // Deviate outside threshold for first 18 hours
        vm.warp(block.timestamp + (18 * 3_600));
        cumulative = _calcCumulative(cellar, cumulative, (18 * 3_600));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier6, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        assertEq(sharePriceOracle.currentIndex(), 3, "Wrong Current Index");

        // For last 6 hours earn no yield.
        cumulative = _calcCumulative(cellar, cumulative, (1 days / 4));
        _passTimeAlterSharePriceAndUpkeep((1 days / 4), sharePriceMultiplier7);

        assertEq(sharePriceOracle.currentIndex(), 4, "Wrong Current Index");

        (uint256 ans, uint256 twaa, bool notSafeToUse) = sharePriceOracle.getLatest();

        assertTrue(!notSafeToUse, "Answer should be safe to use.");
        uint256 expectedTWAA = (cumulative - startingCumulative) / 3 days;

        assertApproxEqAbs(twaa, expectedTWAA, 1, "Actual Time Weighted Average Answer should equal expected.");
        assertApproxEqAbs(
            cellar.previewRedeem(1e6),
            ans.changeDecimals(18, 6),
            1,
            "Actual share price should equal answer."
        );
    }

    function testMultipleReads() external {
        // Rebalance aV2USDC into USDC position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2(USDC, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }
        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        cellar.setHoldingPosition(usdcPosition);

        // Have user deposit into cellar.
        uint256 assets = 1_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);

        uint256 answer;
        uint256 twaa;
        bool isNotSafeToUse;

        for (uint256 i; i < 30; ++i) {
            _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
            (answer, twaa, isNotSafeToUse) = sharePriceOracle.getLatest();
            answer = answer.changeDecimals(18, 6);
            twaa = twaa.changeDecimals(18, 6);
            assertEq(answer, 1e6, "Answer should be 1 USDC");
            assertEq(twaa, 1e6, "TWAA should be 1 USDC");
            assertTrue(!isNotSafeToUse, "Should be safe to use");
        }
    }

    function testGetLatestAnswer() external {
        bool upkeepNeeded;
        bytes memory performData;
        // uint256 checkGas = gasleft();
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        sharePriceOracle.performUpkeep(performData);

        // Fill oracle with observations.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);

        bool isNotSafeToUse;
        (, isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertTrue(!isNotSafeToUse, "Answer should be safe to use.");

        // Make sure `isNotSafeToUse` is true if answer is stale.
        vm.warp(block.timestamp + (1 days + 3_601));
        (, isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertTrue(isNotSafeToUse, "Answer should not be safe to use.");
    }

    function testWrongPerformDataInputs() external {
        cellar.setHoldingPosition(usdcPosition);

        // Have user deposit into cellar.
        uint256 assets = 1e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        // Try calling performUpkeep with a timestamp in the past.
        (uint224 ans, uint64 timestamp) = abi.decode(performData, (uint224, uint64));
        timestamp = timestamp - 100;
        performData = abi.encode(ans, timestamp);
        vm.expectRevert(
            bytes(abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__StalePerformData.selector))
        );
        sharePriceOracle.performUpkeep(performData);

        // Try calling performUpkeep when no upkeep condition is met.
        (ans, timestamp) = abi.decode(performData, (uint224, uint64));
        timestamp = timestamp + 1_000;
        vm.warp(timestamp);
        performData = abi.encode(ans, timestamp);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__NoUpkeepConditionMet.selector)
            )
        );
        sharePriceOracle.performUpkeep(performData);

        // Try calling performUpkeep using a future timestamp.
        (ans, timestamp) = abi.decode(performData, (uint224, uint64));
        timestamp = timestamp + 1_000;
        performData = abi.encode(ans, timestamp);
        vm.expectRevert(
            bytes(abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__FuturePerformData.selector))
        );
        sharePriceOracle.performUpkeep(performData);

        // Try calling performUpkeep from an address that is not the automation registry.
        address attacker = vm.addr(111);
        vm.startPrank(attacker);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ERC4626SharePriceOracle.ERC4626SharePriceOracle__OnlyCallableByAutomationForwarder.selector
                )
            )
        );
        sharePriceOracle.performUpkeep(performData);
        vm.stopPrank();
    }

    function testExtremeLowAnswerTriggersKillSwitch() external {
        cellar.setHoldingPosition(usdcPosition);

        // Have user deposit into cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        _passTimeAlterSharePriceAndUpkeep(1 days, 0.0001e4);

        assertTrue(sharePriceOracle.killSwitch(), "Kill Switch should be active.");
    }

    function testExtremeHighAnswerTriggersKillSwitch() external {
        cellar.setHoldingPosition(usdcPosition);

        // Have user deposit into cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        _passTimeAlterSharePriceAndUpkeep(1 days, 11e4);

        assertTrue(sharePriceOracle.killSwitch(), "Kill Switch should be active.");
    }

    function testMaliciousChainlinkAnswersUpdateAnswerToRightBelowTheExtreme() external {
        cellar.setHoldingPosition(usdcPosition);

        // Have user deposit into cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        // Fill with observations so oracle is safe to use.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);

        // Large proposed answer is passed in, but it is not large enough to trigger kill switch
        _passTimeAlterSharePriceAndUpkeep(1 days, 9e4);
        assertTrue(!sharePriceOracle.killSwitch(), "Kill Switch should not be active.");

        // But if another large answer is provided immediately after, kill switch should be triggered.
        // Eventhough the proposed answer to last saved answer deviation is well below the threshold,
        // the proposed answer compared to TWAA is EXTREME.
        _passTimeAlterSharePriceAndUpkeep(1, 2e4);
        assertTrue(sharePriceOracle.killSwitch(), "Kill Switch should be active.");
    }

    function testKillSwitchEffects() external {
        // Activate Kill Switch.
        cellar.setHoldingPosition(usdcPosition);

        // Have user deposit into cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        // Fill with observations so oracle is safe to use.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);

        bool isNotSafeToUse;
        (, , isNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!isNotSafeToUse, "Oracle should be safe to use.");
        (, isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertTrue(!isNotSafeToUse, "Oracle should be safe to use.");

        // 5 Min pass, but reported answer is extreme.
        _passTimeAlterSharePriceAndUpkeep(300, 11e4);
        assertTrue(sharePriceOracle.killSwitch(), "Kill Switch should be active.");

        // Trying to use the oracle should result in error bool set to true.
        (, , isNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(isNotSafeToUse, "Oracle should not be safe to use.");
        (, isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertTrue(isNotSafeToUse, "Oracle should not be safe to use.");

        (uint216 ans, uint64 time) = abi.decode(performData, (uint216, uint64));
        time = uint64(block.timestamp);
        performData = abi.encode(ans, time);

        // Checkupkeep should return false.
        vm.warp(block.timestamp + 1 days);
        (upkeepNeeded, ) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(!upkeepNeeded, "Upkeep should not be needed.");

        // Perform Upkeep should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__ContractKillSwitch.selector))
        );
        sharePriceOracle.performUpkeep(performData);
    }

    function testSharePriceOracleWorkingWithLargeNumbers() external {
        uint256 assets = 1_000_000_000_000_000e18;
        uint256 sharePriceMultiplier = 1_000_000_000_000e4;

        // Create a new cellar that has WETH as accounting asset.
        string memory cellarName = "WETH Cellar V0.0";
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, WETH, wethPosition, abi.encode(true), assets, platformCut);

        // Create new share price oracle for it.
        {
            ERC4626 _target = ERC4626(address(cellar));
            uint64 _heartbeat = 1 days;
            uint64 _deviationTrigger = 0.0005e4;
            uint64 _gracePeriod = 60 * 60; // 1 hr
            uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
            address _automationRegistry = automationRegistryV2;
            address _automationRegistrar = automationRegistrarV2;
            address _automationAdmin = address(this);

            // Setup share price oracle.
            ERC4626SharePriceOracle.ConstructorArgs memory args = ERC4626SharePriceOracle.ConstructorArgs(
                _target,
                _heartbeat,
                _deviationTrigger,
                _gracePeriod,
                _observationsToUse,
                _automationRegistry,
                _automationRegistrar,
                _automationAdmin,
                address(LINK),
                1e18,
                0,
                1_000_000_000_000_000_000e4,
                address(0),
                0
            );
            sharePriceOracle = new ERC4626SharePriceOracle(args);
        }

        uint96 initialUpkeepFunds = 10e18;
        deal(address(LINK), address(this), initialUpkeepFunds);
        LINK.safeApprove(address(sharePriceOracle), initialUpkeepFunds);
        sharePriceOracle.initialize(initialUpkeepFunds);

        // Write storage to change forwarder to address this.
        stdstore.target(address(sharePriceOracle)).sig(sharePriceOracle.automationForwarder.selector).checked_write(
            address(this)
        );

        // Call first performUpkeep on Cellar.
        {
            bool upkeepNeeded;
            bytes memory performData;
            (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
            assertTrue(upkeepNeeded, "Upkeep should be needed.");
            sharePriceOracle.performUpkeep(performData);
        }

        // Fill with observations so oracle is safe to use.
        _passTimeAlterSharePriceAndUpkeepForWethCellar(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeepForWethCellar(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeepForWethCellar(1 days, 1e4);

        // Shoot the share price to the stratosphere.
        _passTimeAlterSharePriceAndUpkeepForWethCellar(1 days, sharePriceMultiplier);

        // Have TWAA catch up to change in share price.
        _passTimeAlterSharePriceAndUpkeepForWethCellar(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeepForWethCellar(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeepForWethCellar(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeepForWethCellar(1 days, 1e4);

        (uint256 ans, uint256 twaa, ) = sharePriceOracle.getLatest();

        uint256 expectedSharePrice = assets.mulDivDown(sharePriceMultiplier, 1e4) / cellar.totalSupply();
        // To convert it into 1 share.
        expectedSharePrice = expectedSharePrice * 1e18;

        assertEq(ans, expectedSharePrice, "Answer should equal expected.");
        assertEq(ans, twaa, "Answer should equal TWAA.");

        // User can deposit and withdraw.
        assets = 1e18;
        deal(address(WETH), address(this), assets);
        WETH.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));
        cellar.withdraw(assets, address(this), address(this));
    }

    int256 mockSequencerState;
    uint256 mockStartedAt;

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, mockSequencerState, mockStartedAt, 0, 0);
    }

    function testSequencerDown() external {
        // Deploy a new oracle with a sequencer uptime feed set as the test contract address.
        {
            ERC4626 _target = ERC4626(address(cellar));
            uint64 _heartbeat = 1 days;
            uint64 _deviationTrigger = 0.0005e4;
            uint64 _gracePeriod = 60 * 60; // 1 hr
            uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
            address _automationRegistry = automationRegistryV2;
            address _automationRegistrar = automationRegistrarV2;
            address _automationAdmin = address(this);

            // Setup share price oracle.
            ERC4626SharePriceOracle.ConstructorArgs memory args = ERC4626SharePriceOracle.ConstructorArgs(
                _target,
                _heartbeat,
                _deviationTrigger,
                _gracePeriod,
                _observationsToUse,
                _automationRegistry,
                _automationRegistrar,
                _automationAdmin,
                address(LINK),
                1e18,
                0.01e4,
                10e4,
                address(this),
                3_600
            );
            sharePriceOracle = new ERC4626SharePriceOracle(args);
        }

        stdstore.target(address(sharePriceOracle)).sig(sharePriceOracle.automationForwarder.selector).checked_write(
            address(this)
        );

        // Fill oracle with observations.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);

        // Set sequencer state so that it has been up for a year.
        mockSequencerState = 0;
        mockStartedAt = block.timestamp - (365 * 1 days);

        bool isNotSafeToUse;
        (, , isNotSafeToUse) = sharePriceOracle.getLatest();
        assertEq(isNotSafeToUse, false, "Oracle should be safe to use.");

        (, isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertEq(isNotSafeToUse, false, "Oracle should be safe to use.");

        // But if sequencer goes down, isNotSafeToUse is true.
        mockSequencerState = 1;

        (, , isNotSafeToUse) = sharePriceOracle.getLatest();
        assertEq(isNotSafeToUse, true, "Oracle should not be safe to use.");

        (, isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertEq(isNotSafeToUse, true, "Oracle should not be safe to use.");

        // And when sequencer comes back online, we still need to wait the grace period.
        mockSequencerState = 0;
        mockStartedAt = block.timestamp;

        (, , isNotSafeToUse) = sharePriceOracle.getLatest();
        assertEq(isNotSafeToUse, true, "Oracle should not be safe to use.");

        (, isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertEq(isNotSafeToUse, true, "Oracle should not be safe to use.");

        // Wait 1 hour + 1 second(the sequencer grace period set in oracle constructor).
        skip(3_601);

        (, , isNotSafeToUse) = sharePriceOracle.getLatest();
        assertEq(isNotSafeToUse, false, "Oracle should be safe to use.");

        (, isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertEq(isNotSafeToUse, false, "Oracle should be safe to use.");
    }

    function testInitialization() external {
        ERC4626 _target = ERC4626(address(cellar));
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0005e4;
        uint64 _gracePeriod = 60 * 60; // 1 hr
        uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
        address _automationRegistry = automationRegistryV2;
        address _automationRegistrar = automationRegistrarV2;
        address _automationAdmin = address(this);

        // Setup share price oracle.
        ERC4626SharePriceOracle.ConstructorArgs memory args = ERC4626SharePriceOracle.ConstructorArgs(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            _automationRegistrar,
            _automationAdmin,
            address(LINK),
            1e18,
            0.01e4,
            10e4,
            address(0),
            0
        );
        sharePriceOracle = new ERC4626SharePriceOracle(args);

        assertTrue(sharePriceOracle.automationForwarder() == address(0), "Automation Forwarder should not be set.");

        uint96 initialUpkeepFunds = 10e18;
        deal(address(LINK), address(this), initialUpkeepFunds);
        LINK.safeApprove(address(sharePriceOracle), initialUpkeepFunds);
        sharePriceOracle.initialize(initialUpkeepFunds);

        assertTrue(sharePriceOracle.automationForwarder() != address(0), "Automation Forwarder should be set.");

        // Trying to inialtize again should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__AlreadyInitialized.selector))
        );
        sharePriceOracle.initialize(initialUpkeepFunds);

        //Make sure only forwarder can call perform upkeep.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ERC4626SharePriceOracle.ERC4626SharePriceOracle__OnlyCallableByAutomationForwarder.selector
                )
            )
        );
        sharePriceOracle.performUpkeep(performData);

        vm.prank(sharePriceOracle.automationForwarder());
        sharePriceOracle.performUpkeep(performData);
    }

    function testCallingHandlePendingUpkeepWithNothingPending() external {
        ERC4626 _target = ERC4626(address(cellar));
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0005e4;
        uint64 _gracePeriod = 60 * 60; // 1 hr
        uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
        address _automationRegistry = automationRegistryV2;
        address _automationRegistrar = automationRegistrarV2;
        address _automationAdmin = address(this);

        // Setup share price oracle.
        ERC4626SharePriceOracle.ConstructorArgs memory args = ERC4626SharePriceOracle.ConstructorArgs(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            _automationRegistrar,
            _automationAdmin,
            address(LINK),
            1e18,
            0.01e4,
            10e4,
            address(0),
            0
        );
        sharePriceOracle = new ERC4626SharePriceOracle(args);

        // Try calling `handlePendingUpkeep` before calling `initialize`.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ERC4626SharePriceOracle.ERC4626SharePriceOracle__NoPendingUpkeepToHandle.selector
                )
            )
        );
        sharePriceOracle.handlePendingUpkeep(0);

        uint96 initialUpkeepFunds = 10e18;
        deal(address(LINK), address(this), initialUpkeepFunds);
        LINK.safeApprove(address(sharePriceOracle), initialUpkeepFunds);
        sharePriceOracle.initialize(initialUpkeepFunds);

        // Try calling `handlePendingUpkeep` after successfully calling `initialize`.
        // Try calling `handlePendingUpkeep` before calling `initialize`.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ERC4626SharePriceOracle.ERC4626SharePriceOracle__NoPendingUpkeepToHandle.selector
                )
            )
        );
        sharePriceOracle.handlePendingUpkeep(0);
    }

    function testAuotmationDDOSAttackMakingNewUpkeepsPending() external {
        IRegistrar registrarV2 = IRegistrar(automationRegistrarV2);
        IRegistry registryV2 = IRegistry(automationRegistryV2);

        {
            ERC4626 _target = ERC4626(address(cellar));
            uint64 _heartbeat = 1 days;
            uint64 _deviationTrigger = 0.0005e4;
            uint64 _gracePeriod = 60 * 60; // 1 hr
            uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
            address _automationRegistry = automationRegistryV2;
            address _automationRegistrar = automationRegistrarV2;
            address _automationAdmin = address(this);

            // Setup share price oracle.
            ERC4626SharePriceOracle.ConstructorArgs memory args = ERC4626SharePriceOracle.ConstructorArgs(
                _target,
                _heartbeat,
                _deviationTrigger,
                _gracePeriod,
                _observationsToUse,
                _automationRegistry,
                _automationRegistrar,
                _automationAdmin,
                address(LINK),
                1e18,
                0.01e4,
                10e4,
                address(0),
                0
            );
            sharePriceOracle = new ERC4626SharePriceOracle(args);
        }

        IRegistrar.RegistrationParams memory params = IRegistrar.RegistrationParams({
            name: "Share Price Oracle",
            encryptedEmail: hex"",
            upkeepContract: address(sharePriceOracle),
            gasLimit: sharePriceOracle.UPKEEP_GAS_LIMIT(),
            adminAddress: address(this),
            triggerType: 0,
            checkData: hex"",
            triggerConfig: hex"",
            offchainConfig: hex"",
            amount: 10e18
        });
        LINK.safeApprove(automationRegistrarV2, type(uint256).max);
        deal(address(LINK), address(this), type(uint128).max);

        // Create 6 phony upkeeps we will try to use in `handlePendingUpkeep`
        uint256[] memory phonyIds = new uint256[](6);
        params.upkeepContract = address(this);
        phonyIds[0] = registrarV2.registerUpkeep(params);

        params.upkeepContract = address(sharePriceOracle);
        params.gasLimit = 100_000;
        phonyIds[1] = registrarV2.registerUpkeep(params);

        params.gasLimit = sharePriceOracle.UPKEEP_GAS_LIMIT();
        params.adminAddress = address(1);
        phonyIds[2] = registrarV2.registerUpkeep(params);

        params.adminAddress = address(this);
        params.triggerType = 1;
        phonyIds[3] = registrarV2.registerUpkeep(params);

        params.triggerType = 0;
        params.checkData = hex"01";
        phonyIds[4] = registrarV2.registerUpkeep(params);

        params.checkData = hex"";
        params.offchainConfig = hex"01";
        phonyIds[5] = registrarV2.registerUpkeep(params);

        params.offchainConfig = hex"";

        // Set auto-approval to false, so our share price oracle upkeep is made pending.
        vm.startPrank(registrarV2.owner());
        registrarV2.setTriggerConfig(0, IRegistrar.AutoApproveType.DISABLED, 500);
        vm.stopPrank();

        // Now try creating our share price oracle upkeep.
        uint96 initialUpkeepFunds = 10e18;
        deal(address(LINK), address(this), initialUpkeepFunds);
        LINK.safeApprove(address(sharePriceOracle), initialUpkeepFunds);
        sharePriceOracle.initialize(initialUpkeepFunds);

        assertTrue(sharePriceOracle.pendingUpkeepParamHash() != bytes32(0), "Pending param hash should be set");

        // Trying to call initialize again should fail.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__AlreadyInitialized.selector))
        );
        sharePriceOracle.initialize(initialUpkeepFunds);

        // Try using the phony upkeeps to call `handlePendingUpkeep`.
        for (uint256 i; i < phonyIds.length; ++i) {
            vm.expectRevert(
                bytes(
                    abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__ParamHashDiffers.selector)
                )
            );
            sharePriceOracle.handlePendingUpkeep(phonyIds[i]);
        }

        // Approve pending upkeep.
        bytes32 hash = keccak256(
            abi.encode(
                address(sharePriceOracle),
                sharePriceOracle.UPKEEP_GAS_LIMIT(),
                address(this),
                0,
                hex"",
                hex"",
                hex""
            )
        );
        vm.startPrank(registrarV2.owner());

        registrarV2.approve(
            "Simple Aave Cellar V0.0 Share Price Oracle",
            address(sharePriceOracle),
            sharePriceOracle.UPKEEP_GAS_LIMIT(),
            address(this),
            0,
            hex"",
            hex"",
            hex"",
            hash
        );
        vm.stopPrank();

        // This can be pulled from stack trace, if you intentionally add a failing require statement right after the approve call.
        uint256 approvedUpkeepId = 28590879878797250925087462897928979949870272636475581605666189596973513302011;

        // Call `handlePendingUpkeep` with it.
        sharePriceOracle.handlePendingUpkeep(approvedUpkeepId);

        assertTrue(
            sharePriceOracle.automationForwarder() == registryV2.getForwarder(approvedUpkeepId),
            "Automation forwarder should be set."
        );

        // Make sure we can not call `handlePendingUpkeep` again.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ERC4626SharePriceOracle.ERC4626SharePriceOracle__NoPendingUpkeepToHandle.selector
                )
            )
        );
        sharePriceOracle.handlePendingUpkeep(approvedUpkeepId);

        // Make sure we can't call initialize again.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__AlreadyInitialized.selector))
        );
        sharePriceOracle.initialize(initialUpkeepFunds);
    }

    function _passTimeAlterSharePriceAndUpkeepForWethCellar(uint256 timeToPass, uint256 sharePriceMultiplier) internal {
        vm.warp(block.timestamp + timeToPass);
        wethMockFeed.setMockUpdatedAt(block.timestamp);
        deal(address(WETH), address(cellar), WETH.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier, 1e4));

        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
    }

    function _passTimeAlterSharePriceAndUpkeep(uint256 timeToPass, uint256 sharePriceMultiplier) internal {
        vm.warp(block.timestamp + timeToPass);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier, 1e4));

        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
    }

    function _calcCumulative(Cellar target, uint256 previous, uint256 timePassed) internal view returns (uint256) {
        uint256 oneShare = 10 ** target.decimals();
        uint256 totalAssets = target.totalAssets().changeDecimals(target.decimals(), sharePriceOracle.decimals());
        return previous + totalAssets.mulDivDown(oneShare * timePassed, target.totalSupply());
    }
}
