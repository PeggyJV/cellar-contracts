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
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { MockFeesAndReservesAdaptor } from "src/mocks/adaptors/MockFeesAndReservesAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { MockZeroXAdaptor } from "src/mocks/adaptors/MockZeroXAdaptor.sol";

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
    MockZeroXAdaptor private mockZeroXAdaptor;

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

        tracker = new UniswapV3PositionTracker(positionManager);
        erc20Adaptor = new ERC20Adaptor();
        wethVestor = new VestingSimple(WETH, 1 days / 20, 1e16);
        uniswapV3Adaptor = new MockUniswapV3Adaptor();
        aaveATokenAdaptor = new AaveV3ATokenAdaptor();
        aaveDebtTokenAdaptor = new AaveV3DebtTokenAdaptor();
        vestingAdaptor = new VestingSimpleAdaptor();
        mockZeroXAdaptor = new MockZeroXAdaptor();

        // Setup price feeds.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        stor.inETH = true;
        price = uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer());
        price = price.mulDivDown(1743e8, 1e18);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CBETH_ETH_FEED);
        priceRouter.addAsset(cbETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = price.mulDivDown(1743e8, 1e18);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(uniswapV3Adaptor));
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(aaveDebtTokenAdaptor));
        registry.trustAdaptor(address(vestingAdaptor));
        registry.trustAdaptor(address(mockZeroXAdaptor));

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
        cellar.addAdaptorToCatalogue(address(vestingAdaptor));
        cellar.addAdaptorToCatalogue(address(mockZeroXAdaptor));

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
        if (block.number < 16926399) {
            console.log("Use 16926399 for block number");
            return;
        }
        // Make rebalance deviation larger.
        cellar.setRebalanceDeviation(0.02e18);

        // Force whale out of their aCBETH position to make room for our cellar.
        deal(address(WETH), aCBETHWhale, 1_000_000e18);
        vm.startPrank(aCBETHWhale);
        WETH.approve(address(poolV3), type(uint256).max);
        poolV3.supply(address(WETH), 1_000_000e18, aCBETHWhale, 0);
        poolV3.withdraw(address(cbETH), type(uint256).max, aCBETHWhale);
        vm.stopPrank();

        // User deposits into our cellar.
        uint256 assets = 1_000e18;
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Holds multicall call data.
        bytes[] memory rebalanceData;

        // Values needed to make mock zero x swaps.
        bytes memory slippageSwapData;

        // Use Mock Zero X to swap all WETH for cbETH.
        slippageSwapData = abi.encodeWithSignature(
            "slippageSwap(address,address,uint256,uint32)",
            WETH,
            cbETH,
            assets,
            1e4
        );

        // Strategist rebalances to the following.
        // Add cbETH, aCBETH, UniV3 cbETH/WETH, and dWETH as positions.
        // Swap All WETH for cbETH
        // Set Aave V3 EMode to 1.
        // Deposit 70%(of assets) of cbETH into Aave V3
        // Borrow 60%(of assets) of WETH from Aave V3
        // Take half the WETH and pair with remaining cbETH to add liquidity
        // Leave remaining WETH in cellar as exit liquidity.

        rebalanceData = new bytes[](5);
        rebalanceData[0] = abi.encodeWithSelector(Cellar.addPosition.selector, 2, cbEthPosition, abi.encode(0), false);
        rebalanceData[1] = abi.encodeWithSelector(
            Cellar.addPosition.selector,
            3,
            aCbEthPosition,
            abi.encode(1.05e18),
            false
        );
        rebalanceData[2] = abi.encodeWithSelector(
            Cellar.addPosition.selector,
            4,
            cbEthWethPosition,
            abi.encode(0),
            false
        );
        rebalanceData[3] = abi.encodeWithSelector(Cellar.addPosition.selector, 0, dWethPosition, abi.encode(0), true);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](4);

        // Make the 0x swap.
        {
            bytes[] memory adaptorCalls0 = new bytes[](1);
            adaptorCalls0[0] = _createBytesDataToSwapWith0x(WETH, cbETH, assets, slippageSwapData);
            data[0] = Cellar.AdaptorCall({ adaptor: address(mockZeroXAdaptor), callData: adaptorCalls0 });
        }

        // Set EMode to 1, and deposit 70% of cbETH.
        {
            bytes[] memory adaptorCalls1 = new bytes[](2);
            uint256 cbETHToDeposit = priceRouter.getValue(WETH, assets, cbETH).mulDivDown(7, 10);
            adaptorCalls1[0] = _createBytesDataToChangeEMode(1);
            adaptorCalls1[1] = _createBytesDataToLend(cbETH, cbETHToDeposit);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls1 });
        }

        // Borrow 60%(of assets) worth of WETH.
        {
            bytes[] memory adaptorCalls2 = new bytes[](1);
            uint256 wethToBorrow = assets.mulDivDown(6, 10);
            adaptorCalls2[0] = _createBytesDataToBorrow(dWETH, wethToBorrow);
            data[2] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls2 });
        }
        {
            bytes[] memory adaptorCalls3 = new bytes[](1);
            adaptorCalls3[0] = _createBytesDataToOpenLP(cbETH, WETH, 500, type(uint256).max, type(uint256).max, 10);
            data[3] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls3 });
        }

        rebalanceData[4] = abi.encodeWithSelector(Cellar.callOnAdaptor.selector, data);

        // Rebalance the cellar with multicall.
        cellar.multicall(rebalanceData);

        // Strategist is now running there strategy as normal, but UniswapV3 has some exploit making balanceOf revert,
        // so cellar needs to be forced out of the bad position.

        uint256 sharePriceBeforeShutdown = cellar.previewRedeem(1e18);

        // Registry first pauses the cellar.
        address[] memory targets = new address[](1);
        targets[0] = address(cellar);
        registry.batchPause(targets);

        // Registry distrusts position.
        registry.distrustPosition(cbEthWethPosition);

        rebalanceData = new bytes[](6);
        // Somm urges governance to act and fix the cellar.
        rebalanceData[0] = abi.encodeWithSelector(Cellar.toggleIgnorePause.selector, true);
        rebalanceData[1] = abi.encodeWithSelector(Cellar.forcePositionOut.selector, 4, cbEthWethPosition, false);
        // Build callOnAdaptor data to move assets out of uniV3 position, swap to WETH, then vest them, and fix cellar.
        data = new Cellar.AdaptorCall[](3);
        // Withdraw assets from uniswap V3.
        {
            bytes[] memory adaptorCalls0 = new bytes[](1);
            adaptorCalls0[0] = _createBytesDataToCloseLP(address(cellar), 0);
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls0 });
        }
        // Swap cbETH for WETH.
        {
            uint256 amountToSwap = priceRouter.getValue(cbETH, assets.mulDivDown(29, 100), WETH);
            slippageSwapData = abi.encodeWithSignature(
                "slippageSwap(address,address,uint256,uint32)",
                cbETH,
                WETH,
                amountToSwap,
                1e4
            );
            bytes[] memory adaptorCalls1 = new bytes[](1);
            adaptorCalls1[0] = _createBytesDataToSwapWith0x(cbETH, WETH, amountToSwap, slippageSwapData);
            data[1] = Cellar.AdaptorCall({ adaptor: address(mockZeroXAdaptor), callData: adaptorCalls1 });
        }
        // Vest ~808 ETH assets back into the cellar.
        {
            bytes[] memory adaptorCalls2 = new bytes[](1);
            adaptorCalls2[0] = _createBytesDataToVest(wethVestor, 808e18);
            data[2] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls2 });
        }
        rebalanceData[2] = abi.encodeWithSelector(Cellar.callOnAdaptor.selector, data);
        rebalanceData[3] = abi.encodeWithSelector(Cellar.initiateShutdown.selector);
        rebalanceData[4] = abi.encodeWithSelector(Cellar.toggleIgnorePause.selector, false);
        rebalanceData[5] = abi.encodeWithSelector(Cellar.removePositionFromCatalogue.selector, cbEthWethPosition);

        // Fix the cellar with multicall.
        cellar.multicall(rebalanceData);

        // Wait for assets to vest.
        vm.warp(block.timestamp + 1 days / 20);

        // Cellar share price should be recovered at this point, so registry can unpause cellar, and governance can lift shutdown.
        registry.batchUnpause(targets);
        cellar.liftShutdown();

        uint256 sharePriceAfterShutdown = cellar.previewRedeem(1e18);
        assertApproxEqRel(
            sharePriceAfterShutdown,
            sharePriceBeforeShutdown,
            0.001e18,
            "Share price should have recovered once assets vested."
        );
    }

    function testREthStrategy() external {
        if (block.number < 16926399) {
            console.log("Use 16926399 for block number");
            return;
        }
        // Make rebalance deviation larger.
        cellar.setRebalanceDeviation(0.02e18);

        // Force whale out of their aCBETH position to make room for our cellar.
        deal(address(WETH), aCBETHWhale, 1_000_000e18);
        vm.startPrank(aCBETHWhale);
        WETH.approve(address(poolV3), type(uint256).max);
        poolV3.supply(address(WETH), 1_000_000e18, aCBETHWhale, 0);
        poolV3.withdraw(address(cbETH), type(uint256).max, aCBETHWhale);
        vm.stopPrank();

        // User deposits into our cellar.
        uint256 assets = 1_000e18;
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Holds multicall call data.
        bytes[] memory rebalanceData;

        // Values needed to make mock zero x swaps.
        bytes memory slippageSwapData;

        // Use Mock Zero X to swap all WETH for rETH.
        slippageSwapData = abi.encodeWithSignature(
            "slippageSwap(address,address,uint256,uint32)",
            WETH,
            rETH,
            assets,
            1e4
        );

        // Strategist rebalances to the following.
        // Add rETH, aRETH, UniV3 rETH/WETH, and dWETH as positions.
        // Swap All WETH for rETH
        // Deposit 70%(of assets) of rETH into Aave V3
        // Borrow 40%(of assets) of WETH from Aave V3
        // Take half the WETH and pair with remaining rETH to add liquidity
        // Leave remaining WETH in cellar as exit liquidity.

        rebalanceData = new bytes[](5);
        rebalanceData[0] = abi.encodeWithSelector(Cellar.addPosition.selector, 2, rEthPosition, abi.encode(0), false);
        rebalanceData[1] = abi.encodeWithSelector(
            Cellar.addPosition.selector,
            3,
            aREthPosition,
            abi.encode(1.05e18),
            false
        );
        rebalanceData[2] = abi.encodeWithSelector(
            Cellar.addPosition.selector,
            4,
            rEthWethPosition,
            abi.encode(0),
            false
        );
        rebalanceData[3] = abi.encodeWithSelector(Cellar.addPosition.selector, 0, dWethPosition, abi.encode(0), true);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](4);

        // Make the 0x swap.
        {
            bytes[] memory adaptorCalls0 = new bytes[](1);
            adaptorCalls0[0] = _createBytesDataToSwapWith0x(WETH, rETH, assets, slippageSwapData);
            data[0] = Cellar.AdaptorCall({ adaptor: address(mockZeroXAdaptor), callData: adaptorCalls0 });
        }

        // Deposit 70% of rETH.
        {
            bytes[] memory adaptorCalls1 = new bytes[](1);
            uint256 rETHToDeposit = priceRouter.getValue(WETH, assets, rETH).mulDivDown(7, 10);
            adaptorCalls1[0] = _createBytesDataToLend(rETH, rETHToDeposit);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls1 });
        }

        // Borrow 40%(of assets) worth of WETH.
        {
            bytes[] memory adaptorCalls2 = new bytes[](1);
            uint256 wethToBorrow = assets.mulDivDown(4, 10);
            adaptorCalls2[0] = _createBytesDataToBorrow(dWETH, wethToBorrow);
            data[2] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls2 });
        }
        {
            bytes[] memory adaptorCalls3 = new bytes[](1);
            adaptorCalls3[0] = _createBytesDataToOpenLP(rETH, WETH, 500, type(uint256).max, type(uint256).max, 10);
            data[3] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls3 });
        }

        rebalanceData[4] = abi.encodeWithSelector(Cellar.callOnAdaptor.selector, data);

        // Rebalance the cellar with multicall.
        cellar.multicall(rebalanceData);

        // Strategist is now running there strategy as normal, but UniswapV3 adaptor has an exploit,
        // that allows strategists to rug.

        // Registry first pauses the cellar.
        address[] memory targets = new address[](1);
        targets[0] = address(cellar);
        registry.batchPause(targets);

        // Registry distrusts uniswapV3Adaptor.
        registry.distrustAdaptor(address(uniswapV3Adaptor));

        rebalanceData = new bytes[](6);
        // Somm urges governance to act and fix the cellar.
        rebalanceData[0] = abi.encodeWithSelector(Cellar.toggleIgnorePause.selector, true);
        // Build callOnAdaptor data to move assets out of uniV3 position.
        data = new Cellar.AdaptorCall[](1);
        // Withdraw assets from uniswap V3.
        {
            bytes[] memory adaptorCalls0 = new bytes[](1);
            adaptorCalls0[0] = _createBytesDataToCloseLP(address(cellar), 0);
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls0 });
        }
        rebalanceData[1] = abi.encodeWithSelector(Cellar.callOnAdaptor.selector, data);
        rebalanceData[2] = abi.encodeWithSelector(Cellar.toggleIgnorePause.selector, false);
        rebalanceData[3] = abi.encodeWithSelector(Cellar.removePosition.selector, 4, false);
        rebalanceData[4] = abi.encodeWithSelector(
            Cellar.removeAdaptorFromCatalogue.selector,
            address(uniswapV3Adaptor)
        );
        rebalanceData[5] = abi.encodeWithSelector(Cellar.removePositionFromCatalogue.selector, rEthWethPosition);

        // Fix the cellar with multicall.
        cellar.multicall(rebalanceData);

        // At this point strategist can not make calls to old uniswapV3 adaptor, and assets have been moved out of UniV3 position.
        assertEq(
            cellar.adaptorCatalogue(address(uniswapV3Adaptor)),
            false,
            "Uniswap V3 adaptor should not be in the cellars catalogue."
        );

        // Registry can now unpause the cellar since strategist rug vector is mitigated.
        registry.batchUnpause(targets);
    }

    function slippageSwap(ERC20 from, ERC20 to, uint256 inAmount, uint32 slippage) public {
        if (priceRouter.isSupported(from) && priceRouter.isSupported(to)) {
            // Figure out value in, quoted in `to`.
            uint256 fullValueOut = priceRouter.getValue(from, inAmount, to);
            uint256 valueOutWithSlippage = fullValueOut.mulDivDown(slippage, 1e4);
            // Deal caller new balances.
            deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
            deal(address(to), msg.sender, to.balanceOf(msg.sender) + valueOutWithSlippage);
        } else {
            // Pricing is not supported, so just assume exchange rate is 1:1.
            deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
            deal(
                address(to),
                msg.sender,
                to.balanceOf(msg.sender) + inAmount.changeDecimals(from.decimals(), to.decimals())
            );
        }
    }

    // ========================================= HELPER FUNCTIONS =========================================
    function _createBytesDataToVest(VestingSimple _vesting, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(VestingSimpleAdaptor.depositToVesting.selector, address(_vesting), amount);
    }

    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }

    /**
     * @notice Get the upper and lower tick around token0, token1.
     * @param token0 The 0th Token in the UniV3 Pair
     * @param token1 The 1st Token in the UniV3 Pair
     * @param fee The desired fee pool
     * @param size Dictates the amount of ticks liquidity will cover
     *             @dev Must be an even number
     * @param shift Allows the upper and lower tick to be moved up or down relative
     *              to current price. Useful for range orders.
     */
    function _getUpperAndLowerTick(
        ERC20 token0,
        ERC20 token1,
        uint24 fee,
        int24 size,
        int24 shift
    ) internal view returns (int24 lower, int24 upper) {
        uint256 price = priceRouter.getExchangeRate(token1, token0);
        uint256 ratioX192 = ((10 ** token1.decimals()) << 192) / (price);
        uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(ratioX192));
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        tick = tick + shift;

        IUniswapV3Pool pool = IUniswapV3Pool(v3factory.getPool(address(token0), address(token1), fee));
        int24 spacing = pool.tickSpacing();
        lower = tick - (tick % spacing);
        lower = lower - ((spacing * size) / 2);
        upper = lower + spacing * size;
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

    function _createBytesDataToOpenLP(
        ERC20 token0,
        ERC20 token1,
        uint24 poolFee,
        uint256 amount0,
        uint256 amount1,
        int24 size
    ) internal view returns (bytes memory) {
        (int24 lower, int24 upper) = _getUpperAndLowerTick(token0, token1, poolFee, size, 0);
        return
            abi.encodeWithSelector(
                UniswapV3Adaptor.openPosition.selector,
                token0,
                token1,
                poolFee,
                amount0,
                amount1,
                0,
                0,
                lower,
                upper
            );
    }

    function _createBytesDataToCloseLP(address owner, uint256 index) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.closePosition.selector, tokenId, 0, 0);
    }

    function _createBytesDataToAddLP(
        address owner,
        uint256 index,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.addToPosition.selector, tokenId, amount0, amount1, 0, 0);
    }

    function _createBytesDataToTakeLP(
        address owner,
        uint256 index,
        uint256 liquidityPer,
        bool takeFees
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        uint128 liquidity;
        if (liquidityPer >= 1e18) liquidity = type(uint128).max;
        else {
            (, , , , , , , uint128 positionLiquidity, , , , ) = positionManager.positions(tokenId);
            liquidity = uint128((positionLiquidity * liquidityPer) / 1e18);
        }
        return abi.encodeWithSelector(UniswapV3Adaptor.takeFromPosition.selector, tokenId, liquidity, 0, 0, takeFees);
    }

    function _createBytesDataToCollectFees(
        address owner,
        uint256 index,
        uint128 amount0,
        uint128 amount1
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.collectFees.selector, tokenId, amount0, amount1);
    }

    function _createBytesDataToPurgePosition(address owner, uint256 index) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.purgeSinglePosition.selector, tokenId);
    }

    function _createBytesDataToPurgeAllZeroLiquidityPosition(
        ERC20 token0,
        ERC20 token1
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(UniswapV3Adaptor.purgeAllZeroLiquidityPositions.selector, token0, token1);
    }

    function _createBytesDataToRemoveTrackedPositionNotOwned(
        uint256 id,
        ERC20 token0,
        ERC20 token1
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(UniswapV3Adaptor.removeUnOwnedPositionFromTracker.selector, id, token0, token1);
    }

    function _createBytesDataToOpenRangeOrder(
        ERC20 token0,
        ERC20 token1,
        uint24 poolFee,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (bytes memory) {
        int24 lower;
        int24 upper;
        if (amount0 > 0) {
            (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, 100);
        } else {
            (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, -100);
        }

        return
            abi.encodeWithSelector(
                UniswapV3Adaptor.openPosition.selector,
                token0,
                token1,
                poolFee,
                amount0,
                amount1,
                0,
                0,
                lower,
                upper
            );
    }

    function _createBytesDataToSwapWith0x(
        ERC20 tokenIn,
        ERC20 tokenOut,
        uint256 amount,
        bytes memory _swapCallData
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ZeroXAdaptor.swapWith0x.selector, tokenIn, tokenOut, amount, _swapCallData);
    }

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToChangeEMode(uint8 category) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.changeEMode.selector, category);
    }

    function _createBytesDataToWithdraw(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }

    function _createBytesDataToSwapAndRepay(
        ERC20 from,
        ERC20 to,
        uint24 fee,
        uint256 amount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = fee;
        bytes memory params = abi.encode(path, poolFees, amount, 0);
        return
            abi.encodeWithSelector(
                AaveV3DebtTokenAdaptor.swapAndRepay.selector,
                from,
                to,
                amount,
                SwapRouter.Exchange.UNIV3,
                params
            );
    }

    function _createBytesDataToFlashLoan(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    }
}
