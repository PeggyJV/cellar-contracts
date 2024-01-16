// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import {  IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken, IEulerDToken } from "src/interfaces/external/IEuler.sol";

// Import adaptors.
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { EulerETokenAdaptor } from "src/modules/adaptors/Euler/EulerETokenAdaptor.sol";
import { EulerDebtTokenAdaptor } from "src/modules/adaptors/Euler/EulerDebtTokenAdaptor.sol";

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

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/eulerTest/DeployV2.s.sol:DeployV2Script --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployV2Script is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    CellarFactory private factory;
    CellarInitializableV2_1 private cellar;

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;

    Registry private registry;

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IEulerMarkets private markets = IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    address private euler = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    IEulerExec private exec = IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);

    IUniswapV3Factory internal v3factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    IEulerEToken private eUSDC;
    IEulerEToken private eDAI;
    IEulerEToken private eUSDT;

    IEulerDToken private dUSDC;
    IEulerDToken private dDAI;
    IEulerDToken private dUSDT;

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor;
    EulerETokenAdaptor private eulerETokenAdaptor;
    EulerDebtTokenAdaptor private eulerDebtTokenAdaptor;

    // Chainlink PriceFeeds
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

    // Euler positions.
    uint32 private eUsdcPosition;
    uint32 private eDaiPosition;
    uint32 private eUsdtPosition;
    uint32 private eUsdcLiquidPosition;
    uint32 private eDaiLiquidPosition;
    uint32 private eUsdtLiquidPosition;
    uint32 private debtUsdcPosition;
    uint32 private debtDaiPosition;
    uint32 private debtUsdtPosition;

    function run() external {
        vm.startBroadcast();
        // Setup Registry, modules, and adaptors.
        priceRouter = new PriceRouter(registry, WETH);
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        factory = new CellarFactory();
        registry = new Registry(devOwner, address(swapRouter), address(priceRouter));
        erc20Adaptor = new ERC20Adaptor();
        eulerETokenAdaptor = new EulerETokenAdaptor();
        eulerDebtTokenAdaptor = new EulerDebtTokenAdaptor();

        eUSDC = IEulerEToken(markets.underlyingToEToken(address(USDC)));
        eDAI = IEulerEToken(markets.underlyingToEToken(address(DAI)));
        eUSDT = IEulerEToken(markets.underlyingToEToken(address(USDT)));

        dUSDC = IEulerDToken(markets.underlyingToDToken(address(USDC)));
        dDAI = IEulerDToken(markets.underlyingToDToken(address(DAI)));
        dUSDT = IEulerDToken(markets.underlyingToDToken(address(USDT)));

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

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(eulerETokenAdaptor));
        registry.trustAdaptor(address(eulerDebtTokenAdaptor));

        eUsdcPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDC, 0));
        eDaiPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eDAI, 0));
        eUsdtPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDT, 0));
        eUsdcLiquidPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDC, 1));
        eDaiLiquidPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eDAI, 1));
        eUsdtLiquidPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDT, 1));
        debtUsdcPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dUSDC, 0));
        debtDaiPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dDAI, 0));
        debtUsdtPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dUSDT, 0));

        // Deploy cellar using factory.
        factory.adjustIsDeployer(devOwner, true);
        address implementation = address(new CellarInitializableV2_1(registry));

        factory.addImplementation(implementation, 2, 0);

        vm.stopBroadcast();
    }
}
