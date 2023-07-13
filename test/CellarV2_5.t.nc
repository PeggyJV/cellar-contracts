// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

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
            "Simple Cellar",
            "SIMP-CLR",
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

        // Have user deposit into cellar.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        deal(address(USDC), address(cellar), 100e6);

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (uint256 ans, uint256 twaa, bool notSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!notSafeToUse);

        cellar.setSharePriceOracle(sharePriceOracle);
        cellar.toggleRevertOnOracleFailure();

        address newUser = vm.addr(1);
        vm.startPrank(newUser);
        assets = 100e6;
        deal(address(USDC), newUser, assets);
        USDC.approve(address(cellar), assets);
        vm.stopPrank();
    }

    function testNewCellar() external {
        console.log("howdy");
        address newUser = vm.addr(1);
        vm.startPrank(newUser);
        uint256 assets = 100e6;
        uint256 gas = gasleft();
        cellar.deposit(assets, newUser);
        console.log("Gas Used", gas - gasleft());
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
