// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializable } from "src/base/CellarInitializable.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

// Import adaptors.
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { CTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

// Import Compound helpers.
import { CErc20 } from "@compound/CErc20.sol";
import { ComptrollerG7 as Comptroller } from "@compound/ComptrollerG7.sol";

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
 *      `source .env && forge script script/UltimateStablecoinCellar.s.sol:UltimateStablecoinCellarScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 10000000000 --verify --etherscan-api-key $ETHERSCAN_KEY`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract UltimateStablecoinCellarScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private deployer = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    CellarFactory private factory;
    CellarInitializable private cellar;

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;
    VestingSimple private usdcVestor;

    Registry private registry;

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

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor;
    UniswapV3Adaptor private uniswapV3Adaptor;
    AaveATokenAdaptor private aaveATokenAdaptor;
    CTokenAdaptor private cTokenAdaptor;
    VestingSimpleAdaptor private vestingAdaptor;

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
    uint32 private aDAIPosition;
    uint32 private aUSDTPosition;

    // Compound positions.
    uint32 private cUSDCPosition;
    uint32 private cDAIPosition;
    uint32 private cUSDTPosition;

    // Vesting positions.
    uint32 private vUSDCPosition;

    function run() external {
        vm.startBroadcast();
        // Setup Registry, modules, and adaptors.
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        factory = new CellarFactory();
        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            gravityBridge,
            address(swapRouter),
            address(priceRouter)
        );
        usdcVestor = new VestingSimple(USDC, 7 days, 1e6);
        erc20Adaptor = new ERC20Adaptor();
        uniswapV3Adaptor = new UniswapV3Adaptor();
        aaveATokenAdaptor = new AaveATokenAdaptor();
        cTokenAdaptor = new CTokenAdaptor();
        vestingAdaptor = new VestingSimpleAdaptor();

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

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);
        registry.trustAdaptor(address(uniswapV3Adaptor), 0, 0);
        registry.trustAdaptor(address(aaveATokenAdaptor), 0, 0);
        registry.trustAdaptor(address(cTokenAdaptor), 0, 0);
        registry.trustAdaptor(address(vestingAdaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC), 0, 0);
        daiPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(DAI), 0, 0);
        usdtPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDT), 0, 0);
        usdcDaiPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(DAI, USDC), 0, 0);
        usdcUsdtPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(USDC, USDT), 0, 0);
        aUSDCPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aUSDC)), 0, 0);
        aDAIPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aDAI)), 0, 0);
        aUSDTPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aUSDT)), 0, 0);
        cUSDCPosition = registry.trustPosition(address(cTokenAdaptor), abi.encode(address(cUSDC)), 0, 0);
        cDAIPosition = registry.trustPosition(address(cTokenAdaptor), abi.encode(address(cDAI)), 0, 0);
        cUSDTPosition = registry.trustPosition(address(cTokenAdaptor), abi.encode(address(cUSDT)), 0, 0);
        vUSDCPosition = registry.trustPosition(address(vestingAdaptor), abi.encode(usdcVestor), 0, 0);

        // Deploy cellar using factory.
        factory.adjustIsDeployer(deployer, true);
        address implementation = address(new CellarInitializable(registry));

        factory.addImplementation(implementation, 2, 0);

        factory.transferOwnership(sommMultiSig);

        vm.stopBroadcast();
    }
}
