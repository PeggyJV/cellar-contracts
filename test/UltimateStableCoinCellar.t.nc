// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializable } from "src/base/CellarInitializable.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import {  IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { CTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

// Import Compound helpers.
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";

// Import Aave helpers.
import { IPool } from "src/interfaces/external/IPool.sol";

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

contract UltimateStableCoinCellarTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CellarFactory private factory;
    CellarInitializable private cellar;

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;
    VestingSimple private usdcVestor;

    Registry private registry;
    UniswapV3PositionTracker private tracker;

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IUniswapV3Factory internal v3factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    Comptroller private comptroller = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 private dUSDC = ERC20(0x619beb58998eD2278e08620f97007e1116D5D25b);
    ERC20 private aDAI = ERC20(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
    ERC20 private dDAI = ERC20(0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d);
    ERC20 private aUSDT = ERC20(0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811);
    ERC20 private dUSDT = ERC20(0x531842cEbbdD378f8ee36D171d6cC9C4fcf475Ec);
    CErc20 private cUSDC = CErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    CErc20 private cDAI = CErc20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    CErc20 private cUSDT = CErc20(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9);

    address private immutable strategist = vm.addr(0xBEEF);

    address private immutable cosmos = vm.addr(0xCAAA);

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor;
    UniswapV3Adaptor private uniswapV3Adaptor;
    AaveATokenAdaptor private aaveATokenAdaptor;
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor;
    CTokenAdaptor private cTokenAdaptor;
    VestingSimpleAdaptor private vestingAdaptor;
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor;

    // Chainlink PriceFeeds
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private COMP_USD_FEED = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // Base positions.
    uint32 private usdcPosition;
    uint32 private daiPosition;
    uint32 private usdtPosition;

    // Uniswap V3 positions.
    uint32 private usdcDaiPosition;
    uint32 private usdcUsdtPosition;

    // Aave positions.
    uint32 private aUSDCPosition;
    uint32 private dUSDCPosition;
    uint32 private aDAIPosition;
    uint32 private dDAIPosition;
    uint32 private aUSDTPosition;
    uint32 private dUSDTPosition;

    // Compound positions.
    uint32 private cUSDCPosition;
    uint32 private cDAIPosition;
    uint32 private cUSDTPosition;

    // Vesting positions.
    uint32 private vUSDCPosition;

    function setUp() external {
        // Setup Registry, modules, and adaptors.
        priceRouter = new PriceRouter(registry, WETH);
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        factory = new CellarFactory();
        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
        );
        erc20Adaptor = new ERC20Adaptor();
        tracker = new UniswapV3PositionTracker(positionManager);
        usdcVestor = new VestingSimple(USDC, 1 days / 4, 1e6);
        uniswapV3Adaptor = new UniswapV3Adaptor(address(positionManager), address(tracker));
        aaveATokenAdaptor = new AaveATokenAdaptor(address(pool), address(WETH), 1.05e18);
        aaveDebtTokenAdaptor = new AaveDebtTokenAdaptor(address(pool), 1.05e18);
        cTokenAdaptor = new CTokenAdaptor(address(comptroller), address(COMP));
        vestingAdaptor = new VestingSimpleAdaptor();
        swapWithUniswapAdaptor = new SwapWithUniswapAdaptor(uniV2Router, uniV3Router);

        // Setup price feeds.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(COMP_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, COMP_USD_FEED);
        priceRouter.addAsset(COMP, settings, abi.encode(stor), price);

        // Cellar positions array.
        uint32[] memory positions = new uint32[](12);
        uint32[] memory debtPositions = new uint32[](3);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(uniswapV3Adaptor));
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(aaveDebtTokenAdaptor));
        registry.trustAdaptor(address(cTokenAdaptor));
        registry.trustAdaptor(address(vestingAdaptor));
        registry.trustAdaptor(address(swapWithUniswapAdaptor));

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        daiPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(DAI));
        usdtPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDT));
        usdcDaiPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(DAI, USDC));
        usdcUsdtPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(USDC, USDT));
        aUSDCPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aUSDC)));
        dUSDCPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dUSDC)));
        aDAIPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aDAI)));
        dDAIPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dDAI)));
        aUSDTPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aUSDT)));
        dUSDTPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dUSDT)));
        cUSDCPosition = registry.trustPosition(address(cTokenAdaptor), abi.encode(cUSDC));
        cDAIPosition = registry.trustPosition(address(cTokenAdaptor), abi.encode(cDAI));
        cUSDTPosition = registry.trustPosition(address(cTokenAdaptor), abi.encode(cUSDT));
        vUSDCPosition = registry.trustPosition(address(vestingAdaptor), abi.encode(usdcVestor));

        positions[0] = usdcPosition;
        positions[1] = daiPosition;
        positions[2] = usdtPosition;
        positions[3] = usdcDaiPosition;
        positions[4] = usdcUsdtPosition;
        positions[5] = aUSDCPosition;
        positions[6] = aDAIPosition;
        positions[7] = aUSDTPosition;
        positions[8] = cUSDCPosition;
        positions[9] = cDAIPosition;
        positions[10] = cUSDTPosition;
        positions[11] = vUSDCPosition;

        debtPositions[0] = dUSDCPosition;
        debtPositions[1] = dDAIPosition;
        debtPositions[2] = dUSDTPosition;

        bytes[] memory positionConfigs = new bytes[](12);
        bytes[] memory debtConfigs = new bytes[](3);

        uint256 minHealthFactor = 1.1e18;
        positionConfigs[5] = abi.encode(minHealthFactor);

        // Deploy cellar using factory.
        factory.adjustIsDeployer(address(this), true);
        address implementation = address(new CellarInitializable(registry));

        bytes memory initializeCallData = abi.encode(
            registry,
            USDC,
            "Ultimate Stable Coin Cellar",
            "USCC-CLR",
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
        factory.addImplementation(implementation, 2, 0);
        address clone = factory.deploy(2, 0, initializeCallData, USDC, 0, keccak256(abi.encode(2)));
        cellar = CellarInitializable(clone);

        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Setup all the adaptors the cellar will use.
        cellar.addAdaptorToCatalogue(address(uniswapV3Adaptor));
        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(cTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(vestingAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testTotalAssetsFull() external {
        // Create UniV3 positions.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use `callOnAdaptor` to swap and enter 2 different UniV3 positions.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](2);
            adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, assets / 4);
            adaptorCalls[1] = _createBytesDataForSwap(USDC, USDT, 100, assets / 4);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](2);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 30);
            adaptorCalls[1] = _createBytesDataToOpenLP(USDC, USDT, 100, 50_000e6, 50_000e6, 200);
            data[1] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        // Create positions on Aave.
        data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCalls0 = new bytes[](3);
        adaptorCalls0[0] = _createBytesDataToLendOnAave(USDC, 10e6);
        adaptorCalls0[1] = _createBytesDataToLendOnAave(DAI, 10e18);
        adaptorCalls0[2] = _createBytesDataToLendOnAave(USDT, 10e6);
        bytes[] memory adaptorCalls1 = new bytes[](3);
        adaptorCalls1[0] = _createBytesDataToBorrow(dUSDC, 1e6);
        adaptorCalls1[1] = _createBytesDataToBorrow(dDAI, 1e18);
        adaptorCalls1[2] = _createBytesDataToBorrow(dUSDT, 1e6);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls0 });
        data[1] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls1 });
        cellar.callOnAdaptor(data);

        // Create positions on Compound.
        // Mint cellar $2 of each stable.
        deal(address(USDC), address(cellar), 2e6);
        deal(address(DAI), address(cellar), 2e18);
        deal(address(USDT), address(cellar), 2e6);
        data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](3);
        adaptorCalls[0] = _createBytesDataToLendOnCompound(cUSDC, 1e6);
        adaptorCalls[1] = _createBytesDataToLendOnCompound(cDAI, 1e18);
        adaptorCalls[2] = _createBytesDataToLendOnCompound(cUSDT, 1e6);

        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 gas = gasleft();
        uint256 totalAssets = cellar.totalAssets();
    }

    function testUltimateStableCoinCellar() external {
        // Start by managing credit positions to reflect the following.
        // 0) Vesting USDC
        // 1) Compound USDC (holding position)
        // 2) Aave USDC
        // 3) Uniswap V3 DAI/USDC LP
        // 4) Uniswap V3 USDC/USDT LP
        // debt positions
        // 0) Aave debt USDT
        // Swap cUSDC and DAI position.
        cellar.swapPositions(1, 8, false);
        // Change holding position to index 1
        cellar.setHoldingPosition(cUSDCPosition);
        // Swap USDC and vesting USDC positions.
        cellar.swapPositions(0, 11, false);
        // Swap USDT position and aUSDC.
        cellar.swapPositions(2, 5, false);
        // Uniswap V3 positions are already in their correct spot.
        // Remove unused credit positions.
        for (uint256 i; i < 7; i++) cellar.removePosition(5, false);
        // Remove unused debt positions.
        cellar.removePosition(0, true); // Removes dUSDC
        cellar.removePosition(0, true); // Removes dDAI
        // Have whale join the cellar with 10M USDC.
        uint256 assets = 10_000_000e6;
        address whale = vm.addr(777);
        deal(address(USDC), whale, assets);
        vm.startPrank(whale);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, whale);
        vm.stopPrank();
        // Change rebalance deviation to 1% so we can do more stuff during the rebalance.
        cellar.setRebalanceDeviation(0.01e18);
        // Strategist manages cellar in order to achieve the following portfolio.
        // ~40% in cUSDC.
        // ~30% Uniswap V3 DAI/USDC 0.01% and 0.05% LP
        // ~30% Uniswap V3 USDC/USDT 0.01% and 0.05% LP
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](6);
        // Create data to withdraw 80% of assets from compound.
        {
            uint256 amountToWithdraw = assets.mulDivDown(8, 10);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompound(cUSDC, amountToWithdraw);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        // Create data to lend 20% of assets on Aave.
        {
            uint256 amountToLend = assets.mulDivDown(2, 10);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnAave(USDC, amountToLend);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }
        // Create data to swap and add liquidity to Uniswap V3.
        {
            uint256 usdcToUse = assets.mulDivDown(15, 100);
            {
                bytes[] memory adaptorCalls = new bytes[](2);
                adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, usdcToUse);
                adaptorCalls[1] = _createBytesDataForSwap(USDC, USDT, 100, usdcToUse);
                data[2] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
            }
            // Since we are dividing the USDC into 2 LP positions each, cut it in half.
            usdcToUse = usdcToUse / 2;
            {
                bytes[] memory adaptorCalls = new bytes[](4);
                adaptorCalls[0] = _createBytesDataToOpenLP(DAI, USDC, 100, type(uint256).max, usdcToUse, 30);
                adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 500, type(uint256).max, usdcToUse, 40);
                adaptorCalls[2] = _createBytesDataToOpenLP(USDC, USDT, 100, usdcToUse, type(uint256).max, 20);
                adaptorCalls[3] = _createBytesDataToOpenLP(USDC, USDT, 500, usdcToUse, type(uint256).max, 80);
                data[3] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
            }
        }
        // Swap remaining DAI and USDT for USDC
        {
            bytes[] memory adaptorCalls = new bytes[](2);
            adaptorCalls[0] = _createBytesDataForSwap(USDT, USDC, 100, type(uint256).max);
            adaptorCalls[1] = _createBytesDataForSwap(DAI, USDC, 500, type(uint256).max);
            data[4] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        //Lend USDC on Compound.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnCompound(cUSDC, type(uint256).max);
            data[5] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        // Perform all adaptor operations to move into desired positions.
        cellar.callOnAdaptor(data);
        // Generate some Compound, and Uniswap V3 earnings.
        // Manipulate Comptroller storage to give Cellar some pending COMP.
        // uint256 compReward = 100e18;
        // stdstore
        //     .target(address(comptroller))
        //     .sig(comptroller.compAccrued.selector)
        //     .with_key(address(cellar))
        //     .checked_write(compReward);
        // // Have test contract perform a ton of swaps in Uniswap V3 DAI/USDC and USDC/USDT pools.
        // uint256 assetsToSwap = 100_000_000e6;
        // deal(address(USDC), address(this), assetsToSwap);
        // address[] memory path0 = new address[](2);
        // path0[0] = address(USDC);
        // path0[1] = address(DAI);
        // address[] memory path1 = new address[](2);
        // path1[0] = address(USDC);
        // path1[1] = address(USDT);
        // address[] memory path2 = new address[](2);
        // path2[0] = address(DAI);
        // path2[1] = address(USDC);
        // address[] memory path3 = new address[](2);
        // path3[0] = address(USDT);
        // path3[1] = address(USDC);
        // uint24[] memory poolFees = new uint24[](1);
        // bytes memory swapData;
        // poolFees[0] = 100;
        // USDC.safeApprove(address(swapRouter), type(uint256).max);
        // DAI.safeApprove(address(swapRouter), type(uint256).max);
        // USDT.safeApprove(address(swapRouter), type(uint256).max);
        // for (uint256 i = 0; i < 10; i++) {
        //     uint256 swapAmount = assetsToSwap / 2;
        //     swapData = abi.encode(path0, poolFees, swapAmount, 0);
        //     uint256 daiAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, DAI);
        //     swapData = abi.encode(path1, poolFees, swapAmount, 0);
        //     uint256 usdtAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, USDT);
        //     swapData = abi.encode(path2, poolFees, daiAmount, 0);
        //     assetsToSwap = swapRouter.swapWithUniV3(swapData, address(this), DAI, USDC);
        //     swapData = abi.encode(path3, poolFees, usdtAmount, 0);
        //     assetsToSwap += swapRouter.swapWithUniV3(swapData, address(this), USDT, USDC);
        // }
        // data = new Cellar.AdaptorCall[](3);
        // // Create data to claim COMP rewards.
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     address[] memory path = new address[](3);
        //     path[0] = address(COMP);
        //     path[1] = address(WETH);
        //     path[2] = address(USDC);
        //     uint24[] memory poolFees0 = new uint24[](2);
        //     poolFees0[0] = 3000;
        //     poolFees0[1] = 500;
        //     bytes memory params = abi.encode(path, poolFees0, 0, 0);
        //     adaptorCalls[0] = abi.encodeWithSelector(
        //         CTokenAdaptor.claimCompAndSwap.selector,
        //         USDC,
        //         SwapRouter.Exchange.UNIV3,
        //         params,
        //         0.90e18
        //     );
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        // }
        // // Create data to claim Uniswap V3 fees.
        // {
        //     bytes[] memory adaptorCalls = new bytes[](4);
        //     adaptorCalls[0] = _createBytesDataToCollectFees(address(cellar), 0, type(uint128).max, type(uint128).max);
        //     adaptorCalls[1] = _createBytesDataToCollectFees(address(cellar), 2, type(uint128).max, type(uint128).max);
        //     adaptorCalls[2] = _createBytesDataForOracleSwap(DAI, USDC, 100, type(uint256).max); // Swap all DAI for USDC.
        //     adaptorCalls[3] = _createBytesDataForOracleSwap(USDT, USDC, 100, type(uint256).max); // Swap all USDT for USDC.
        //     data[1] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        // }
        // // Create data to vest all rewards.
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     // Deposit all Idle USDC into Vesting Contract.
        //     adaptorCalls[0] = abi.encodeWithSelector(
        //         VestingSimpleAdaptor.depositToVesting.selector,
        //         usdcVestor,
        //         type(uint256).max
        //     );
        //     data[2] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        // }
        // Perform all adaptor operations to claim rewards/fees, and vest them.
        // cellar.callOnAdaptor(data);
        // vm.warp(block.timestamp + 1 days / 4);
    }

    // ========================================= HELPER FUNCTIONS =========================================
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

        IUniswapV3Pool targetPool = IUniswapV3Pool(v3factory.getPool(address(token0), address(token1), fee));
        int24 spacing = targetPool.tickSpacing();
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
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV3.selector, path, poolFees, fromAmount, 0);
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
        uint256 liquidityPer
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        (, , , , , , , uint128 positionLiquidity, , , , ) = positionManager.positions(tokenId);
        uint128 liquidity = uint128((positionLiquidity * liquidityPer) / 1e18);
        return abi.encodeWithSelector(UniswapV3Adaptor.takeFromPosition.selector, tokenId, liquidity, 0, 0);
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

    function _createBytesDataToLendOnAave(
        ERC20 tokenToLend,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToWithdrawFromAave(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }

    function _createBytesDataToFlashLoan(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    }

    function _createBytesDataToLendOnCompound(
        CErc20 market,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.depositToCompound.selector, market, amountToLend);
    }

    function _createBytesDataToWithdrawFromCompound(
        CErc20 market,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.withdrawFromCompound.selector, market, amountToWithdraw);
    }

    function _createBytesDataToClaimComp() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.claimComp.selector);
    }
}
