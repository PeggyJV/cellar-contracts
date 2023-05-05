// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Arbitrum/DeployRealYieldUsd.s.sol:DeployRealYieldUsdScript --rpc-url $ARBITRUM_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployRealYieldUsdScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0x913Cfec274dB5D0766744a7E7EDf9c05b6dA02B0;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    uint8 public CHAINLINK_DERIVATIVE = 1;

    ERC20 public WETH = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ERC20 public WBTC = ERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    ERC20 public USDC = ERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    ERC20 public USDT = ERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    ERC20 public DAI = ERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

    // Aave V3 positions.
    ERC20 public aV3USDC = ERC20(0x625E7708f30cA75bfd92586e17077590C60eb4cD);
    ERC20 public dV3USDC = ERC20(0xFCCf3cAbbe80101232d343252614b6A3eE81C989);
    ERC20 public aV3USDT = ERC20(0x6ab707Aca953eDAeFBc4fD23bA73294241490620);
    ERC20 public aV3DAI = ERC20(0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE);
    ERC20 public aV3WETH = ERC20(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8);
    ERC20 public dV3WETH = ERC20(0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351);
    ERC20 public aV3WBTC = ERC20(0x078f358208685046a11C85e8ad32895DED33A249);
    ERC20 public dV3WBTC = ERC20(0x92b42c66840C7AD907b4BF74879FF3eF7c529473);

    // Datafeeds
    address public WETH_USD_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address public WBTC_USD_FEED = 0x6ce185860a4963106506C203335A2910413708e9;
    address public USDC_USD_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address public USDT_USD_FEED = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
    address public DAI_USD_FEED = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    CellarInitializableV2_2 private cellar;

    PriceRouter private priceRouter = PriceRouter(0xC8a0ca81EbaDC043AF0eD8c9D96AD80fCBEac53a);
    CellarFactory private factory = CellarFactory(0x596dD1506b6f14B73746D73c90283A2A3991B364);
    Registry private registry = Registry(0x1b38148B8DfdeA0B3D80C45F0d8569889504f0B5);
    // FeesAndReserves private feesAndReserves = FeesAndReserves(0xF4279E93a06F9d4b5d0625b1F471AA99Ef9B686b);
    UniswapV3PositionTracker private tracker = UniswapV3PositionTracker(0xB5C3bF7050465aE66233983D7cb1F14eEB2508a1);

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor = ERC20Adaptor(0x5C42C8b4142d89312dB1C070391b3976baFd9053);
    // FeesAndReservesAdaptor private feesAndReservesAdaptor;
    AaveV3ATokenAdaptor private aaveV3ATokenAdaptor = AaveV3ATokenAdaptor(0x5F7b564acFdA73E448d16BFa20016c1787214795);
    AaveV3DebtTokenAdaptor private aaveV3DebtTokenAdaptor =
        AaveV3DebtTokenAdaptor(0x7c0ec72f7F101F6Dee3F0Da337C9e46BC73672CD);
    UniswapV3Adaptor private uniswapV3Adaptor;
    ZeroXAdaptor private zeroXAdaptor = ZeroXAdaptor(0x6b7f87279982d919Bbf85182DDeAB179B366D8f2);
    OneInchAdaptor private oneInchAdaptor = OneInchAdaptor(0x6E2dAc3b9E9ADc0CbbaE2D0B9Fd81952a8D33872);

    function run() external {
        vm.startBroadcast();
        // Initial Deployment.
        // registry = new Registry(devOwner, address(0), address(0));

        // priceRouter = new PriceRouter();

        // registry.setAddress(2, address(priceRouter));

        // factory = new CellarFactory();

        // // feesAndReserves = new FeesAndReserves(address(0));
        // tracker = new UniswapV3PositionTracker(positionManager);

        // // Setup pricing.
        // PriceRouter.ChainlinkDerivativeStorage memory stor;

        // PriceRouter.AssetSettings memory settings;

        // uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        // priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        // priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        // priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        // priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        // priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);

        // // Deploy adaptors.
        // erc20Adaptor = new ERC20Adaptor();
        // aaveV3ATokenAdaptor = new AaveV3ATokenAdaptor();
        // aaveV3DebtTokenAdaptor = new AaveV3DebtTokenAdaptor();
        // zeroXAdaptor = new ZeroXAdaptor();
        // oneInchAdaptor = new OneInchAdaptor();

        // uint32[] memory positionIds = new uint32[](13);
        // // Add some positions.
        // registry.trustAdaptor(address(erc20Adaptor));
        // registry.trustAdaptor(address(aaveV3ATokenAdaptor));
        // registry.trustAdaptor(address(aaveV3DebtTokenAdaptor));
        // registry.trustAdaptor(address(zeroXAdaptor));
        // registry.trustAdaptor(address(oneInchAdaptor));
        // positionIds[0] = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        // positionIds[1] = registry.trustPosition(address(erc20Adaptor), abi.encode(USDT));
        // positionIds[2] = registry.trustPosition(address(erc20Adaptor), abi.encode(DAI));
        // positionIds[3] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3USDC));
        // positionIds[4] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3USDT));
        // positionIds[5] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3DAI));
        // positionIds[6] = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        // positionIds[7] = registry.trustPosition(address(erc20Adaptor), abi.encode(WBTC));
        // positionIds[8] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3WETH));
        // positionIds[9] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3WBTC));
        // positionIds[10] = registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(dV3WETH));
        // positionIds[11] = registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(dV3WBTC));
        // positionIds[12] = registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(dV3USDC));

        // // Deploy new Cellar implementation.
        // CellarInitializableV2_2 implementation = new CellarInitializableV2_2(registry);

        // bytes memory params = abi.encode(
        //     address(0),
        //     registry,
        //     WETH,
        //     "Test Implementation",
        //     "Test Imp",
        //     positionIds[6],
        //     abi.encode(0),
        //     address(0)
        // );

        // implementation.initialize(params);

        // factory.addImplementation(address(implementation), 2, 2);

        // Deploy some cellars.
        uniswapV3Adaptor = new UniswapV3Adaptor();

        uint32[] memory positionIds = new uint32[](2);
        registry.trustAdaptor(address(uniswapV3Adaptor));
        positionIds[0] = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(USDT, USDC));
        positionIds[1] = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(DAI, USDC));

        // Positions start at 101 USDC
        factory.adjustIsDeployer(devOwner, true);

        // Test real yield usd
        bytes memory params = abi.encode(devOwner, registry, USDC, "PepeUSD", "P-USD", 101, abi.encode(0), strategist);

        address ryusd = factory.deploy(2, 2, params, USDC, 0, keccak256(abi.encode(block.timestamp)));

        CellarInitializableV2_2 cellar = CellarInitializableV2_2(ryusd);
        cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveV3DebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(uniswapV3Adaptor));
        cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
        cellar.addAdaptorToCatalogue(address(oneInchAdaptor));

        cellar.addPositionToCatalogue(102);
        cellar.addPositionToCatalogue(103);
        cellar.addPositionToCatalogue(104);
        cellar.addPositionToCatalogue(105);
        cellar.addPositionToCatalogue(106);
        cellar.addPositionToCatalogue(114);
        cellar.addPositionToCatalogue(115);

        cellar.transferOwnership(strategist);

        bytes memory patParams = abi.encode(
            devOwner,
            registry,
            USDC,
            "Test Trader",
            "Test Trader",
            101,
            abi.encode(0),
            strategist
        );
        address pat = factory.deploy(2, 2, patParams, USDC, 0, keccak256(abi.encode(block.timestamp + 1)));

        cellar = CellarInitializableV2_2(pat);
        cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveV3DebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
        cellar.addAdaptorToCatalogue(address(oneInchAdaptor));

        cellar.addPositionToCatalogue(107);
        cellar.addPositionToCatalogue(108);
        cellar.addPositionToCatalogue(109);
        cellar.addPositionToCatalogue(110);
        cellar.addPositionToCatalogue(111);
        cellar.addPositionToCatalogue(112);
        cellar.addPositionToCatalogue(113);

        cellar.transferOwnership(strategist);

        vm.stopBroadcast();
    }
}
