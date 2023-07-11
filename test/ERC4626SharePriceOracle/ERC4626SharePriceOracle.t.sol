// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { ERC4626SharePriceOracle } from "src/base/CellarV2_5/ERC4626SharePriceOracle.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract ERC4626SharePriceOracleTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    AaveATokenAdaptor private aaveATokenAdaptor;
    ERC20Adaptor private erc20Adaptor;
    MockDataFeed private usdcMockFeed;
    Cellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;
    ERC4626SharePriceOracle private sharePriceOracle;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private aWETH = ERC20(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e);
    ERC20 private aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 private dUSDC = ERC20(0x619beb58998eD2278e08620f97007e1116D5D25b);
    ERC20 private dWETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private aWBTC = ERC20(0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656);
    ERC20 private TUSD = ERC20(0x0000000000085d4780B73119b644AE5ecd22b376);
    ERC20 private aTUSD = ERC20(0x101cc05f4A51C0319f570d5E146a8C625198e636);
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
    uint32 private aUSDCPosition;
    uint32 private debtUSDCPosition;

    function setUp() external {
        usdcMockFeed = new MockDataFeed(USDC_USD_FEED);
        aaveATokenAdaptor = new AaveATokenAdaptor(address(pool), address(WETH), 1.05e18);
        erc20Adaptor = new ERC20Adaptor();
        priceRouter = new PriceRouter(registry, WETH);

        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(usdcMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(usdcMockFeed));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](2);
        uint32[] memory debtPositions;

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(erc20Adaptor));

        aUSDCPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aUSDC)));
        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(address(USDC)));

        positions[0] = aUSDCPosition;
        positions[1] = usdcPosition;

        bytes[] memory positionConfigs = new bytes[](2);
        bytes[] memory debtConfigs;

        uint256 minHealthFactor = 1.1e18;
        positionConfigs[0] = abi.encode(minHealthFactor);

        cellar = new Cellar(
            registry,
            USDC,
            "Simple Aave Cellar",
            "AAVE-CLR",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                aUSDCPosition,
                address(0),
                type(uint128).max,
                type(uint128).max
            )
        );

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        ERC4626 _target = ERC4626(address(cellar));
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0005e4;
        uint64 _gracePeriod = 60 * 60; // 1 hr
        uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
        address _automationRegistry = address(this);

        // Setup share price oracle.
        sharePriceOracle = new ERC4626SharePriceOracle(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry
        );
    }

    function testHappyPath() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(aUSDC.balanceOf(address(cellar)), assets, 1, "Assets should have been deposited into Aave.");

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

        uint256 currentSharePrice = cellar.previewRedeem(1e18);

        // Get time weighted average share price.
        // uint256 gas = gasleft();
        (uint256 ans, uint256 timeWeightedAverageAnswer, bool notSafeToUse) = sharePriceOracle.getLatest();
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

        // Assume an attack found some way to alter the target Cellar share price, and they also have a way to suppress
        // Chainlink Automation upkeeps to prevent the upkeep from running.
        uint256 maxTime = 1 days + 3600; // Heartbeat + grace period
        _passTimeAlterSharePriceAndUpkeep(maxTime + suppressionTime, 0.5e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        // Attackers TWAA value is not safe to use, recover, and advance time forward.
        _passTimeAlterSharePriceAndUpkeep(1 days, 2e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(checkNotSafeToUse, "Value should not be safe to use");

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (answer, twaa, checkNotSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!checkNotSafeToUse, "Value should be safe to use");

        assertEq(answer, twaa, "Answer should eqaul TWAA since attacker answer is thrown out");
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
        cellar.setHoldingPosition(usdcPosition);

        sharePriceMultiplier0 = bound(sharePriceMultiplier0, 0.8e4, 1.5e4);
        sharePriceMultiplier1 = bound(sharePriceMultiplier1, 0.8e4, 1.5e4);
        uint256 sharePriceMultiplier2 = sharePriceMultiplier0 / 2;
        uint256 sharePriceMultiplier3 = sharePriceMultiplier0 / 3;
        uint256 sharePriceMultiplier4 = sharePriceMultiplier0 / 4;
        uint256 sharePriceMultiplier5 = (sharePriceMultiplier1 * 1.1e4) / 1e4;
        uint256 sharePriceMultiplier6 = (sharePriceMultiplier1 * 1.2e4) / 1e4;
        uint256 sharePriceMultiplier7 = (sharePriceMultiplier1 * 1.3e4) / 1e4;

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

        uint256 startingCumulative = cellar.previewRedeem(1e18) * (block.timestamp - 1);
        uint256 cumulative = startingCumulative;

        // Deviate outside threshold for first 12 hours
        vm.warp(block.timestamp + (1 days / 2));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier0, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
        cumulative += cellar.previewRedeem(1e18) * (1 days / 2);

        assertEq(sharePriceOracle.currentIndex(), 1, "Wrong Current Index");

        // For last 12 hours, reset to original share price.
        _passTimeAlterSharePriceAndUpkeep((1 days / 2), sharePriceMultiplier1);
        cumulative += cellar.previewRedeem(1e18) * (1 days / 2);

        assertEq(sharePriceOracle.currentIndex(), 2, "Wrong Current Index");

        // Deviate outside threshold for first 6 hours
        vm.warp(block.timestamp + (1 days / 4));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier2, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
        cumulative += cellar.previewRedeem(1e18) * (1 days / 4);

        assertEq(sharePriceOracle.currentIndex(), 2, "Wrong Current Index");

        // Deviate outside threshold for first 6-12 hours
        vm.warp(block.timestamp + (1 days / 4));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier3, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
        cumulative += cellar.previewRedeem(1e18) * (1 days / 4);

        assertEq(sharePriceOracle.currentIndex(), 2, "Wrong Current Index");

        // Deviate outside threshold for 12-18 hours
        vm.warp(block.timestamp + (1 days / 4));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier4, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
        cumulative += cellar.previewRedeem(1e18) * (1 days / 4);

        assertEq(sharePriceOracle.currentIndex(), 2, "Wrong Current Index");

        // For last 6 hours show a loss.
        _passTimeAlterSharePriceAndUpkeep((1 days / 4), sharePriceMultiplier5);
        cumulative += cellar.previewRedeem(1e18) * (1 days / 4);

        assertEq(sharePriceOracle.currentIndex(), 3, "Wrong Current Index");

        // Deviate outside threshold for first 18 hours
        vm.warp(block.timestamp + (18 * 3_600));
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier6, 1e4));
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
        cumulative += cellar.previewRedeem(1e18) * (18 * 3_600);

        assertEq(sharePriceOracle.currentIndex(), 3, "Wrong Current Index");

        // For last 6 hours earn no yield.
        _passTimeAlterSharePriceAndUpkeep((1 days / 4), sharePriceMultiplier7);
        cumulative += cellar.previewRedeem(1e18) * (1 days / 4);

        assertEq(sharePriceOracle.currentIndex(), 4, "Wrong Current Index");

        (uint256 ans, uint256 twaa, bool notSafeToUse) = sharePriceOracle.getLatest();

        assertTrue(!notSafeToUse, "Answer should be safe to use.");
        uint256 expectedTWAA = (cumulative - startingCumulative) / 3 days;

        assertEq(twaa, expectedTWAA, "Actual Time Weighted Average Answer should equal expected.");
        assertEq(cellar.previewRedeem(1e18), ans, "Actual share price should equal answer.");
    }

    function testMultipleReads() external {
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
            assertEq(answer, 1e6, "Answer should be 1 USDC");
            assertEq(twaa, 1e6, "TWAA should be 1 USDC");
            assertTrue(!isNotSafeToUse, "Should be safe to use");
        }
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
        performData = abi.encode(ans, timestamp);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__NoUpkeepConditionMet.selector)
            )
        );
        sharePriceOracle.performUpkeep(performData);

        // Try calling performUpkeep from an address that is not the automation registry.
        address attacker = vm.addr(111);
        vm.startPrank(attacker);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ERC4626SharePriceOracle.ERC4626SharePriceOracle__OnlyCallableByAutomationRegistry.selector
                )
            )
        );
        sharePriceOracle.performUpkeep(performData);
        vm.stopPrank();
    }

    // TODO test verifying that the shortest period an observation can be is heartbeat
    // TODO test checking to see if we ever have a scenario where an upkeep is triggered by the answer heartbeat check, but not triggered by the previous observation heartbeat check

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

    // TODO add worst case scenario test where days pass and the upkeep is not working.
    // What should happen is it should revert until it has enough fresh days of data that it can safely get a TWAP.
}
