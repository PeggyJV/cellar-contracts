// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { AaveV2EnableAssetAsCollateralAdaptor } from "src/modules/adaptors/Aave/AaveV2EnableAssetAsCollateralAdaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken, IEulerDToken } from "src/interfaces/external/IEuler.sol";

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RealYeildGovTest is Test {
    using Math for uint256;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 public LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);
    ERC20 public ONEINCH = ERC20(0x111111111117dC0aa78b770fA6A738034120C302);
    ERC20 public UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 public SNX = ERC20(0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F);
    ERC20 public ENS = ERC20(0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72);
    ERC20 public MKR = ERC20(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);
    ERC20 public AAVE = ERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
    ERC20 public LDO = ERC20(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32);
    ERC20 public WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 public CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 public stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    // Aave V2 Positions.
    ERC20 public aV2WETH = ERC20(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e);
    ERC20 public aV2WBTC = ERC20(0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656);
    ERC20 public aV2ONEINCH = ERC20(0xB29130CBcC3F791f077eAdE0266168E808E5151e);
    ERC20 public aV2LINK = ERC20(0xa06bC25B5805d5F8d82847D191Cb4Af5A3e873E0);
    ERC20 public aV2UNI = ERC20(0xB9D7CB55f463405CDfBe4E90a6D2Df01C2B92BF1);
    ERC20 public aV2SNX = ERC20(0x35f6B052C598d933D69A4EEC4D04c73A191fE6c2);
    ERC20 public aV2ENS = ERC20(0x9a14e23A58edf4EFDcB360f68cd1b95ce2081a2F);

    ERC20 public dV2WETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);

    // Aave V3 positions.
    ERC20 public aV3WETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public aV3WBTC = ERC20(0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8);
    ERC20 public aV3SNX = ERC20(0xC7B4c17861357B8ABB91F25581E7263E08DCB59c);
    ERC20 public aV3UNI = ERC20(0xF6D2224916DDFbbab6e6bd0D1B7034f4Ae0CaB18);
    ERC20 public aV3LINK = ERC20(0x5E8C8A7243651DB1384C0dDfDbE39761E8e7E51a);

    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);

    address public ONEINCH_USD_FEED = 0xc929ad75B72593967DE83E7F7Cda0493458261D9;
    address public SNX_USD_FEED = 0xDC3EA94CD0AC27d9A86C180091e7f78C683d3699;
    address public ENS_USD_FEED = 0x5C00128d4d1c2F4f652C267d7bcdD7aC99C16E16;
    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    CellarInitializableV2_2 private rye = CellarInitializableV2_2(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;

    // Define Adaptors.
    CellarAdaptor private cellarAdaptor = CellarAdaptor(0x24EEAa1111DAc1c0fE0Cf3c03bBa03ADde1e7Fe4);
    ERC20Adaptor private erc20Adaptor = ERC20Adaptor(0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE);
    FeesAndReservesAdaptor private feesAndReservesAdaptor =
        FeesAndReservesAdaptor(0x647d264d800A2461E594796af61a39b7735d8933);
    AaveATokenAdaptor private aaveATokenAdaptor = AaveATokenAdaptor(0xe3A3b8AbbF3276AD99366811eDf64A0a4b30fDa2);
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor =
        AaveDebtTokenAdaptor(0xeC86ac06767e911f5FdE7cba5D97f082C0139C01);
    AaveV3ATokenAdaptor private aaveV3ATokenAdaptor = AaveV3ATokenAdaptor(0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6);
    AaveV3DebtTokenAdaptor private aaveV3DebtTokenAdaptor =
        AaveV3DebtTokenAdaptor(0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7);
    UniswapV3Adaptor private uniswapV3Adaptor = UniswapV3Adaptor(0x0bD9a2c1917E3a932A4a712AEE38FF63D35733Fb);
    ZeroXAdaptor private zeroXAdaptor = ZeroXAdaptor(0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef);
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor =
        SwapWithUniswapAdaptor(0xd6BC6Df1ed43e3101bC27a4254593a06598a3fDD);
    OneInchAdaptor private oneInchAdaptor = OneInchAdaptor(0xB8952ce4010CFF3C74586d712a4402285A3a3AFb);
    AaveV2EnableAssetAsCollateralAdaptor private aaveV2EnableAssetAsCollateralAdaptor =
        AaveV2EnableAssetAsCollateralAdaptor(0x724FEb5819D1717Aec5ADBc0974a655a498b2614);

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    SwapRouter private swapRouter = SwapRouter(0x070f43E613B33aD3EFC6B2928f3C01d58D032020);

    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    CellarFactory private factory = CellarFactory(0x9D30672eED8D514cD1ad009Cfe85Ea8f0019D37F);

    address private implementation = 0x3A763A9db61f4C8B57d033aC11d74e5c9fB3314f;

    CellarInitializableV2_2 private cellar;

    function setUp() external {}

    /**
    Run `source .env && forge test -vvv --fork-url $MAINNET_RPC_URL --fork-block-number 17345875 --match-path test/testIntegrations/RealYieldGov.t.sol --watch --match-test testHunch`
    To see prices
     */
    function testHunch() external {
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256[] memory prices = new uint256[](10);
        console.log("---------1INCH-----------");
        // uint256 startingPrice = uint256(IChainlinkAggregator(ONEINCH_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ONEINCH_USD_FEED);
        // prices[0] = startingPrice.mulDivDown(0.80e4, 1e4);
        // for (uint256 i = 1; i < prices.length; ++i) prices[i] = prices[i - 1].mulDivDown(1.02e4, 0.98e4);
        // for (uint256 i; i < prices.length; ++i) {
        //     console.log("Min", prices[i].mulDivDown(0.98e4, 1e4));
        //     console.log("Max", prices[i].mulDivDown(1.02e4, 1e4));
        // }
        // console.log("----------SNX----------");
        // startingPrice = uint256(IChainlinkAggregator(SNX_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, SNX_USD_FEED);
        // prices[0] = startingPrice.mulDivDown(0.80e4, 1e4);
        // for (uint256 i = 1; i < prices.length; ++i) prices[i] = prices[i - 1].mulDivDown(1.02e4, 0.98e4);
        // for (uint256 i; i < prices.length; ++i) {
        //     console.log("Min", prices[i].mulDivDown(0.98e4, 1e4));
        //     console.log("Max", prices[i].mulDivDown(1.02e4, 1e4));
        // }
        // console.log("----------ENS----------");
        // startingPrice = uint256(IChainlinkAggregator(ENS_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ENS_USD_FEED);
        // prices[0] = startingPrice.mulDivDown(0.80e4, 1e4);
        // for (uint256 i = 1; i < prices.length; ++i) prices[i] = prices[i - 1].mulDivDown(1.02e4, 0.98e4);
        // for (uint256 i; i < prices.length; ++i) {
        //     console.log("Min", prices[i].mulDivDown(0.98e4, 1e4));
        //     console.log("Max", prices[i].mulDivDown(1.02e4, 1e4));
        // }

        uint256 startingPrice = uint256(IChainlinkAggregator(ONEINCH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ONEINCH_USD_FEED);
        prices[0] = startingPrice.mulDivDown(0.80e4, 1e4);
        for (uint256 i = 1; i < prices.length; ++i) prices[i] = prices[i - 1].mulDivDown(1.02e4, 0.98e4);
        for (uint256 i; i < prices.length; ++i) {
            console.log(prices[i]);
        }
        // priceRouter.addAsset(ONEINCH, settings, abi.encode(stor), price);
        console.log("----------SNX----------");
        startingPrice = uint256(IChainlinkAggregator(SNX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, SNX_USD_FEED);
        prices[0] = startingPrice.mulDivDown(0.80e4, 1e4);
        for (uint256 i = 1; i < prices.length; ++i) prices[i] = prices[i - 1].mulDivDown(1.02e4, 0.98e4);
        for (uint256 i; i < prices.length; ++i) {
            console.log(prices[i]);
        }
        // priceRouter.addAsset(SNX, settings, abi.encode(stor), price);
        console.log("----------ENS----------");
        startingPrice = uint256(IChainlinkAggregator(ENS_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ENS_USD_FEED);
        prices[0] = startingPrice.mulDivDown(0.80e4, 1e4);
        for (uint256 i = 1; i < prices.length; ++i) prices[i] = prices[i - 1].mulDivDown(1.02e4, 0.98e4);
        for (uint256 i; i < prices.length; ++i) {
            console.log(prices[i]);
        }
    }

    function testRegistryCalls() external {
        uint32[] memory positionIds = new uint32[](10);
        vm.startPrank(multisig);
        registry.trustAdaptor(address(cellarAdaptor));

        // credit positions
        positionIds[0] = registry.trustPosition(address(cellarAdaptor), abi.encode(address(rye)));
        // positionIds[1] = registry.trustPosition(address(erc20Adaptor), abi.encode(WBTC));
        positionIds[2] = registry.trustPosition(address(erc20Adaptor), abi.encode(LINK));
        positionIds[3] = 123; //registry.trustPosition(address(erc20Adaptor), abi.encode(UNI));
        // positionIds[4] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(aV2WBTC));
        positionIds[5] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(aV2LINK));
        positionIds[6] = 133; //registry.trustPosition(address(aaveATokenAdaptor), abi.encode(aV2UNI));
        // positionIds[7] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3WBTC));
        positionIds[8] = 136; //registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3UNI));
        positionIds[9] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3LINK));

        vm.stopPrank();

        uint32 aV3dWETH = 114;
        uint32 aV2dWETH = 119;
        uint32 WETHposition = 101;
        uint32 STETHPosition = 104;
        uint32 aV2STETHPosition = 118;
        vm.startPrank(devOwner);
        {
            // Deploy cellar using factory.
            bytes memory initializeCallData = abi.encode(
                devOwner,
                registry,
                LINK,
                "Real Yield LINK",
                "RYLINK",
                positionIds[2],
                abi.encode(0),
                strategist
            );
            address imp = factory.getImplementation(2, 2);
            require(imp != address(0), "Invalid implementation");

            uint256 initialDeposit = 0;
            address clone = factory.deploy(
                2,
                2,
                initializeCallData,
                LINK,
                initialDeposit,
                keccak256(abi.encode(block.timestamp))
            );
            cellar = CellarInitializableV2_2(clone);

            // Setup all the adaptors the cellar will use.
            cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveV3DebtTokenAdaptor));
            cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
            cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
            cellar.addAdaptorToCatalogue(address(oneInchAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveV2EnableAssetAsCollateralAdaptor));

            // Setup all the positions the cellar will use.
            cellar.addPositionToCatalogue(positionIds[5]);
            cellar.addPositionToCatalogue(positionIds[9]);
            cellar.addPositionToCatalogue(aV3dWETH);
            cellar.addPositionToCatalogue(aV2dWETH);
            cellar.addPositionToCatalogue(WETHposition);
            cellar.addPositionToCatalogue(STETHPosition);
            cellar.addPositionToCatalogue(aV2STETHPosition);

            // cellar.transferOwnership(0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138);
        }

        {
            // Deploy cellar using factory.
            bytes memory initializeCallData = abi.encode(
                devOwner,
                registry,
                UNI,
                "Real Yield UNI",
                "RYUNI",
                positionIds[3],
                abi.encode(0),
                strategist
            );
            address imp = factory.getImplementation(2, 2);
            require(imp != address(0), "Invalid implementation");

            uint256 initialDeposit = 0;
            address clone = factory.deploy(
                2,
                2,
                initializeCallData,
                UNI,
                initialDeposit,
                keccak256(abi.encode(block.timestamp + 1))
            );
            cellar = CellarInitializableV2_2(clone);

            // Setup all the adaptors the cellar will use.
            cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveV3DebtTokenAdaptor));
            cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
            cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
            cellar.addAdaptorToCatalogue(address(aaveV2EnableAssetAsCollateralAdaptor));
            cellar.addAdaptorToCatalogue(address(oneInchAdaptor));

            // Setup all the positions the cellar will use.
            cellar.addPositionToCatalogue(positionIds[6]);
            cellar.addPositionToCatalogue(positionIds[8]);
            cellar.addPositionToCatalogue(aV2dWETH);
            cellar.addPositionToCatalogue(aV3dWETH);
            cellar.addPositionToCatalogue(WETHposition);
            cellar.addPositionToCatalogue(STETHPosition);
            cellar.addPositionToCatalogue(aV2STETHPosition);

            // cellar.transferOwnership(0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138);
        }

        // {
        //     // Deploy cellar using factory.
        //     bytes memory initializeCallData = abi.encode(
        //         devOwner,
        //         registry,
        //         WBTC,
        //         "Real Yield BTC",
        //         "RYBTC",
        //         positionIds[1],
        //         abi.encode(0),
        //         strategist
        //     );
        //     address imp = factory.getImplementation(2, 2);
        //     require(imp != address(0), "Invalid implementation");

        //     uint256 initialDeposit = 0;
        //     address clone = factory.deploy(
        //         2,
        //         2,
        //         initializeCallData,
        //         WBTC,
        //         initialDeposit,
        //         keccak256(abi.encode(block.timestamp + 2))
        //     );
        //     cellar = CellarInitializableV2_2(clone);

        //     // Setup all the adaptors the cellar will use.
        //     cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));
        //     cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        //     cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        //     cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
        //     cellar.addAdaptorToCatalogue(address(aaveV3DebtTokenAdaptor));
        //     cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
        //     cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
        //     cellar.addAdaptorToCatalogue(address(aaveV2EnableAssetAsCollateralAdaptor));
        //     cellar.addAdaptorToCatalogue(address(oneInchAdaptor));

        //     // Setup all the positions the cellar will use.
        //     cellar.addPositionToCatalogue(positionIds[4]);
        //     cellar.addPositionToCatalogue(positionIds[7]);
        //     cellar.addPositionToCatalogue(aV2dWETH);
        //     cellar.addPositionToCatalogue(aV3dWETH);
        //     cellar.addPositionToCatalogue(WETHposition);
        //     cellar.addPositionToCatalogue(STETHPosition);
        //     cellar.addPositionToCatalogue(aV2STETHPosition);

        //     // cellar.transferOwnership(0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138);
        // }
        vm.stopPrank();
    }

    // function testLinkRealYieldGov() external {
    //     if (block.number < 17034079) {
    //         console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17034079.");
    //         return;
    //     }
    //     uint256 assets = 10_000e18;
    //     deal(address(LINK), address(this), assets);
    //     LINK.approve(address(cellar), assets);
    //     cellar.deposit(assets, address(this));

    //     // Rebalance Cellar into RYE.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         uint256 amountToBorrow = priceRouter.getValue(LINK, assets / 2, WETH);
    //         adaptorCalls[0] = _createBytesDataToBorrow(dV3WETH, amountToBorrow);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(aaveV3DebtTokenAdaptor), callData: adaptorCalls });
    //     }
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToDepositIntoCellar(rye, type(uint256).max);
    //         data[1] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
    //     }

    //     cellar.callOnAdaptor(data);

    //     vm.warp(block.timestamp + 1 days / 2);

    //     uint256 assetsToWithdraw = cellar.maxWithdraw(address(this));
    //     cellar.withdraw(assetsToWithdraw, address(this), address(this));
    //     console.log("WETH", WETH.balanceOf(address(this)));
    // }

    // ========================================= HELPER FUNCTIONS =========================================

    function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToDepositIntoCellar(Cellar target, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CellarAdaptor.depositToCellar.selector, target, amount);
    }

    function _createBytesDataForSwap(ERC20 from, ERC20 to, uint256 fromAmount) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV2.selector, path, fromAmount, 0);
    }

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToWithdrawFromAaveV3(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }
}
