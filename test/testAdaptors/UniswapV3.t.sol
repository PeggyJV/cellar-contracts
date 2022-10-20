// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, IGravity } from "src/base/Cellar.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { LockedERC4626 } from "src/mocks/LockedERC4626.sol";
import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

// Will test the swapping and cellar position management using adaptors
contract CellarAssetManagerTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MockCellar private cellar;
    MockGravity private gravity;

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;

    Registry private registry;

    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    ERC20 private LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    address private immutable strategist = vm.addr(0xBEEF);

    address private immutable cosmos = vm.addr(0xCAAA);

    UniswapV3Adaptor private uniswapV3Adaptor;
    ERC20Adaptor private erc20Adaptor;

    uint256 private usdcPosition;
    uint256 private wethPosition;
    uint256 private daiPosition;
    uint256 private usdcDaiPosition;
    uint256 private usdcWethPosition;

    function setUp() external {
        // Setup Registry and modules:
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        gravity = new MockGravity();
        uniswapV3Adaptor = new UniswapV3Adaptor();
        erc20Adaptor = new ERC20Adaptor();

        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
        );

        priceRouter.addAsset(USDC, 0, 0, false, 0);
        priceRouter.addAsset(DAI, 0, 0, false, 0);
        priceRouter.addAsset(WETH, 0, 0, false, 0);

        // Cellar positions array.
        uint256[] memory positions = new uint256[](5);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(uniswapV3Adaptor), 0, 0);
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(USDC), 0, 0);
        daiPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(DAI), 0, 0);
        wethPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(WETH), 0, 0);
        usdcDaiPosition = registry.trustPosition(address(uniswapV3Adaptor), false, abi.encode(DAI, USDC), 0, 0);
        usdcWethPosition = registry.trustPosition(address(uniswapV3Adaptor), false, abi.encode(USDC, WETH), 0, 0);

        positions[0] = usdcPosition;
        positions[1] = daiPosition;
        positions[2] = wethPosition;
        positions[3] = usdcDaiPosition;
        positions[4] = usdcWethPosition;

        bytes[] memory positionConfigs = new bytes[](5);

        cellar = new MockCellar(
            registry,
            USDC,
            positions,
            positionConfigs,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            strategist
        );
        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Allow cellar to use CellarAdaptor so it can swap ERC20's and enter/leave other cellar positions.
        cellar.setupAdaptor(address(uniswapV3Adaptor));

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        // Manipulate  test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        cellar.setRebalanceDeviation(0.1e18);

        // console.log("What", registry.getAddress(2));
    }

    // ========================================== REBALANCE TEST ==========================================
    //TODO add tests for multiple positions with same underlying
    function testRebalanceIntoUniswapV3PositionUSDC_DAI() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        int24 tick;
        {
            //Find current tick USDC WETH is trading at.
            uint256 price = priceRouter.getExchangeRate(USDC, DAI);

            // uint160 sqrtPriceX96 = uint160(getSqrtPriceX96(1e6, price));
            uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(price) << 96);

            tick = getTick(sqrtPriceX96);
            if (tick < 0) {
                console.log("Current Tick (-)", uint24(-1 * tick));
            } else console.log("Current Tick", uint24(tick));
        }

        {
            //Find current tick USDC WETH is trading at.
            uint256 price = priceRouter.getExchangeRate(DAI, USDC);

            // uint160 sqrtPriceX96 = uint160(getSqrtPriceX96(1e6, price));
            uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(price) << 96);

            tick = getTick(sqrtPriceX96);
            if (tick < 0) {
                console.log("Current Tick (-)", uint24(-1 * tick));
            } else console.log("Current Tick", uint24(tick));
        }

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(DAI);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 100;
        // Swap 50,500 USDC to insure we have atleast 50k USDC and 50k DAI.
        bytes memory params = abi.encode(path, poolFees, 50_500e6, 0);
        adaptorCalls[0] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            DAI,
            50_500e6,
            SwapRouter.Exchange.UNIV3,
            params
        );
        adaptorCalls[1] = abi.encodeWithSelector(
            UniswapV3Adaptor.openPosition.selector,
            DAI,
            USDC,
            uint24(100),
            50_000e18,
            50_000e6,
            0,
            0,
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        console.log("Total Assets", cellar.totalAssets());
    }

    function testHunch() external {
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: address(DAI),
            token1: address(USDC),
            fee: 100
        });
        address factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address pool = (PoolAddress.computeAddress(factory, poolKey));
        console.log("Pool", pool);
        deal(address(DAI), address(uniswapV3Adaptor), 101_000e18);
        deal(address(USDC), address(uniswapV3Adaptor), 101_000e6);
        uniswapV3Adaptor.openPosition(
            DAI,
            USDC,
            uint24(500),
            5_000e18,
            5_000e6,
            0,
            0,
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }

    function testRebalanceIntoUniswapV3PositionUSDC_WETH() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));
        int24 tick;
        {
            //Find current tick USDC WETH is trading at.
            uint256 price = priceRouter.getExchangeRate(WETH, USDC);

            // uint160 sqrtPriceX96 = uint160(getSqrtPriceX96(1e6, price));
            uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(price) << 96);

            tick = getTick(sqrtPriceX96);
            if (tick < 0) {
                console.log("Current Tick (-)", uint24(-1 * tick));
            } else console.log("Current Tick", uint24(tick));
        }

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 500;
        // Swap 50,500 USDC to insure we have atleast 50k USDC and 50k DAI.
        bytes memory params = abi.encode(path, poolFees, 50_500e6, 0);
        adaptorCalls[0] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            WETH,
            50_500e6,
            SwapRouter.Exchange.UNIV3,
            params
        );
        adaptorCalls[1] = abi.encodeWithSelector(
            UniswapV3Adaptor.openPosition.selector,
            USDC,
            WETH,
            uint24(500), //TODO changing this to 500 causes mint to fail
            50_000e6,
            45e18,
            0,
            0,
            204669, // TickMath.MIN_TICK + 500_000, // tick - 10, //TODO doing this causes mint to use half of available assets, seems to change the decimals returned in balanceOf, and the other half of assets are no longer in the cellar
            204679 // TickMath.MAX_TICK - 500_000 // tick + 10
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function testRebalanceIntoMultipleDifferentUniswapV3Position() external {
        deal(address(USDC), address(this), 201_000e6);
        cellar.deposit(201_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](4);
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 500;
        // Swap 50,500 USDC to insure we have atleast 50k USDC and 50k DAI.
        bytes memory params = abi.encode(path, poolFees, 50_500e6, 0);
        adaptorCalls[0] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            WETH,
            50_500e6,
            SwapRouter.Exchange.UNIV3,
            params
        );
        path[0] = address(USDC);
        path[1] = address(DAI);
        poolFees = new uint24[](1);
        poolFees[0] = 100;
        // Swap 50,500 USDC to insure we have atleast 50k USDC and 50k DAI.
        params = abi.encode(path, poolFees, 50_500e6, 0);
        adaptorCalls[1] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            DAI,
            50_500e6,
            SwapRouter.Exchange.UNIV3,
            params
        );
        adaptorCalls[2] = abi.encodeWithSelector(
            UniswapV3Adaptor.openPosition.selector,
            USDC,
            WETH,
            uint24(100), // 0.3%
            50_000e6,
            45e18,
            0,
            0,
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
        adaptorCalls[3] = abi.encodeWithSelector(
            UniswapV3Adaptor.openPosition.selector,
            DAI,
            USDC,
            uint24(100), // 0.01%
            50_000e18,
            50_000e6,
            0,
            0,
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        console.log("Total Assets", cellar.totalAssets());
    }

    function testMultipleUniV3PositionsWithSameUnderlying() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](3);
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(DAI);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 100;
        // Swap 50,500 USDC to insure we have atleast 50k USDC and 50k DAI.
        bytes memory params = abi.encode(path, poolFees, 50_500e6, 0);
        adaptorCalls[0] = abi.encodeWithSelector(
            BaseAdaptor.swap.selector,
            USDC,
            DAI,
            50_500e6,
            SwapRouter.Exchange.UNIV3,
            params
        );
        adaptorCalls[1] = abi.encodeWithSelector(
            UniswapV3Adaptor.openPosition.selector,
            DAI,
            USDC,
            uint24(100),
            25_000e18,
            25_000e6,
            0,
            0,
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
        adaptorCalls[2] = abi.encodeWithSelector(
            UniswapV3Adaptor.openPosition.selector,
            DAI,
            USDC,
            uint24(100),
            25_000e18,
            25_000e6,
            0,
            0,
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        console.log("Total Assets", cellar.totalAssets());
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

    //Helper functions
    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }

    function getSqrtPriceX96(uint256 priceA, uint256 priceB) internal pure returns (uint256) {
        uint256 ratioX192 = (priceA << 192) / (priceB);
        return _sqrt(ratioX192);
    }

    function getTick(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }
}
