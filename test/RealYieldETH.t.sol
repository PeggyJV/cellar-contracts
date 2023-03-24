// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { MockUniswapV3Adaptor } from "src/mocks/adaptors/MockUniswapV3Adaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { MockFeesAndReservesAdaptor } from "src/mocks/adaptors/MockFeesAndReservesAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

// Import Aave helpers.
import { IPool } from "src/interfaces/external/IPool.sol";
import { IPoolV3 } from "src/interfaces/external/IPoolV3.sol";

// Import UniV3 helpers.
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

// Import test helpers
import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RealYieldETHTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CellarFactory private factory;
    CellarInitializableV2_2 private cellar;

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;
    VestingSimple private wethVestor;
    FeesAndReserves private feesAndReserves;
    UniswapV3PositionTracker private tracker;

    Registry private registry;

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IUniswapV3Factory internal v3factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IPoolV3 private poolV3 = IPoolV3(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);

    // Aave V3 Markets.
    ERC20 public aWETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public dWETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    ERC20 public aCBETH = ERC20(0x977b6fc5dE62598B08C85AC8Cf2b745874E8b78c);
    ERC20 public aRETH = ERC20(0xCc9EE9483f662091a1de4795249E24aC0aC2630f);

    address private immutable strategist = vm.addr(0xBEEF);

    address private immutable cosmos = vm.addr(0xCAAA);

    // Whale has supplied about 3k cbETH on Aave V3.
    address private aCBETHWhale = 0x42d0ed91b55065fABCfB9ab3516437D01430C0E6;

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor;
    MockUniswapV3Adaptor private uniswapV3Adaptor;
    AaveV3ATokenAdaptor private aaveATokenAdaptor;
    AaveV3DebtTokenAdaptor private aaveDebtTokenAdaptor;
    VestingSimpleAdaptor private vestingAdaptor;
    FeesAndReservesAdaptor private feesAndReservesAdaptor;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public CBETH_ETH_FEED = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address public RETH_ETH_FEED = 0x536218f9E9Eb48863970252233c8F271f554C2d0;

    // Base positions.
    uint32 private wethPosition;
    uint32 private cbEthPosition;
    uint32 private rEthPosition;

    // Uniswap V3 positions.
    uint32 private cbEthWethPosition;
    uint32 private rEthWethPosition;

    // Aave V3 positions.
    uint32 private aWethPosition;
    uint32 private dWethPosition;
    uint32 private aCbEthPosition;
    uint32 private aREthPosition;

    // Vesting positions.
    uint32 private vWethPosition;

    function setUp() external {
        // Setup Registry, modules, and adaptors.
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        factory = new CellarFactory();
        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
        );
        feesAndReserves = new FeesAndReserves(registry);

        erc20Adaptor = new ERC20Adaptor();
        tracker = new UniswapV3PositionTracker(positionManager);
        wethVestor = new VestingSimple(WETH, 1 days / 4, 1e16);
        uniswapV3Adaptor = new MockUniswapV3Adaptor();
        aaveATokenAdaptor = new AaveV3ATokenAdaptor();
        aaveDebtTokenAdaptor = new AaveV3DebtTokenAdaptor();
        vestingAdaptor = new VestingSimpleAdaptor();
        feesAndReservesAdaptor = new FeesAndReservesAdaptor();

        // Setup price feeds.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        stor.inETH = true;
        price = uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer());
        price = price.mulDivDown(1786e8, 1e18);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CBETH_ETH_FEED);
        priceRouter.addAsset(cbETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = price.mulDivDown(1786e8, 1e18);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(uniswapV3Adaptor));
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(aaveDebtTokenAdaptor));
        registry.trustAdaptor(address(feesAndReservesAdaptor));
        registry.trustAdaptor(address(vestingAdaptor));

        wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        cbEthPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(cbETH));
        rEthPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(rETH));
        cbEthWethPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(cbETH, WETH));
        rEthWethPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(rETH, WETH));
        aWethPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aWETH)));
        dWethPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dWETH)));
        aCbEthPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aCBETH)));
        aREthPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aRETH)));
        vWethPosition = registry.trustPosition(address(vestingAdaptor), abi.encode(wethVestor));

        // Deploy cellar using factory.
        factory.adjustIsDeployer(address(this), true);
        address implementation = address(new CellarInitializableV2_2(registry));

        bytes memory initializeCallData = abi.encode(
            address(this),
            registry,
            WETH,
            "Real Yield ETH",
            "RYE",
            wethPosition,
            abi.encode(1.05e18),
            strategist
        );
        factory.addImplementation(implementation, 2, 0);
        address clone = factory.deploy(2, 0, initializeCallData, WETH, 0, keccak256(abi.encode(2)));
        cellar = CellarInitializableV2_2(clone);

        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Setup all the adaptors the cellar will use.
        cellar.addAdaptorToCatalogue(address(uniswapV3Adaptor));
        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));
        cellar.addAdaptorToCatalogue(address(vestingAdaptor));

        // Setup cellars position catalogue.
        cellar.addPositionToCatalogue(vWethPosition);
        cellar.addPositionToCatalogue(cbEthPosition);
        cellar.addPositionToCatalogue(rEthPosition);
        cellar.addPositionToCatalogue(cbEthWethPosition);
        cellar.addPositionToCatalogue(rEthWethPosition);
        cellar.addPositionToCatalogue(aWethPosition);
        cellar.addPositionToCatalogue(dWethPosition);
        cellar.addPositionToCatalogue(aCbEthPosition);
        cellar.addPositionToCatalogue(aREthPosition);

        cellar.addPosition(0, vWethPosition, abi.encode(0), false);

        // Approve cellar to spend all assets.
        WETH.approve(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testCbEthStrategy() external {
        // Start by adding positions.
        cellar.addPosition(2, cbEthPosition, abi.encode(0), false);
        cellar.addPosition(3, aCbEthPosition, abi.encode(1.05e18), false);
        cellar.addPosition(4, cbEthWethPosition, abi.encode(0), false);
        cellar.addPosition(0, dWethPosition, abi.encode(0), true);

        // Force whale out of their aCBETH position to make room for our cellar.
        deal(address(WETH), aCBETHWhale, 1_000_000e18);
        vm.startPrank(aCBETHWhale);
        WETH.approve(address(poolV3), type(uint256).max);
        poolV3.supply(address(WETH), 1_000_000e18, aCBETHWhale, 0);
        poolV3.withdraw(address(cbETH), type(uint256).max, aCBETHWhale);
        vm.stopPrank();
    }

    function testREthStrategy() external {
        // Start by adding positions.
        cellar.addPosition(2, rEthPosition, abi.encode(0), false);
        cellar.addPosition(3, aREthPosition, abi.encode(1.05e18), false);
        cellar.addPosition(4, rEthWethPosition, abi.encode(0), false);

        cellar.addPosition(0, dWethPosition, abi.encode(0), true);
    }

    // TODO add tests where we handle bad adaptors, and bad positions with and without cooperating strategists
}
