// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import { Deployer } from "src/Deployer.sol";
import { Math } from "src/utils/Math.sol";
import { ArbitrumAddresses } from "test/resources/ArbitrumAddresses.sol";
import { Deployer } from "src/Deployer.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { CellarWithOracleWithBalancerFlashLoans } from "src/base/permutations/CellarWithOracleWithBalancerFlashLoans.sol";

import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";

import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/Arbitrum/DeployV2_5.s.sol:DeployV2_5Script --rpc-url $ARBITRUM_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 100000000 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployV2_5Script is Script, ArbitrumAddresses {
    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    Registry public registry = Registry(0x43BD96931A47FBABd50727F6982c796B3C9A974C);
    PriceRouter public priceRouter;
    Deployer public deployer = Deployer(deployerAddress);

    ERC20Adaptor public erc20Adaptor;
    UniswapV3PositionTracker public uniswapV3PositionTracker;
    UniswapV3Adaptor public uniswapV3Adaptor;
    UniswapV3PositionTracker public sushiswapV3PositionTracker;
    UniswapV3Adaptor public sushiswapV3Adaptor;
    AaveV3ATokenAdaptor public aaveV3ATokenAdaptor;
    AaveV3DebtTokenAdaptor public aaveV3DebtTokenAdaptor;
    OneInchAdaptor public oneInchAdaptor;
    ZeroXAdaptor public zeroXAdaptor;

    CellarWithOracleWithBalancerFlashLoans public ryUsdCellar;

    // Define positions.

    // ERC20
    uint32 public wethPosition = 1;
    uint32 public usdcPosition = 2;
    uint32 public usdcePosition = 3;
    uint32 public daiPosition = 4;
    uint32 public usdtPosition = 5;

    // Uniswap
    uint32 public usdcUsdceUniPosition = 1_000_001;
    uint32 public usdcDaiUniPosition = 1_000_002;
    uint32 public usdcUsdtUniPosition = 1_000_003;
    uint32 public daiUsdceUniPosition = 1_000_004;
    uint32 public usdtUsdceUniPosition = 1_000_005;

    // Sushi
    uint32 public usdcUsdceSushiPosition = 1_250_001;
    uint32 public usdcDaiSushiPosition = 1_250_002;
    uint32 public usdcUsdtSushiPosition = 1_250_003;
    uint32 public daiUsdceSushiPosition = 1_250_004;
    uint32 public usdtUsdceSushiPosition = 1_250_005;

    // Aave
    uint32 public aV3WethPosition = 2_000_001;
    uint32 public aV3UsdcPosition = 2_000_002;
    uint32 public aV3UsdcePosition = 2_000_003;
    uint32 public aV3DaiPosition = 2_000_004;
    uint32 public aV3UsdtPosition = 2_000_005;
    uint32 public dV3WethPosition = 2_500_001;
    uint32 public dV3UsdcPosition = 2_500_002;
    uint32 public dV3UsdcePosition = 2_500_003;
    uint32 public dV3DaiPosition = 2_500_004;
    uint32 public dV3UsdtPosition = 2_500_005;

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast();

        // // Deploy registry.
        // creationCode = type(Registry).creationCode;
        // constructorArgs = abi.encode(dev, dev, dev, dev);
        // registry = Registry(deployer.deployContract("Test Registry V0.0", creationCode, constructorArgs, 0));

        // // Deploy price router.
        // creationCode = type(PriceRouter).creationCode;
        // constructorArgs = abi.encode(dev, registry, WETH);
        // priceRouter = PriceRouter(deployer.deployContract("Test PriceRouter V0.0", creationCode, constructorArgs, 0));

        // // Update price router in registry.
        // registry.setAddress(2, address(priceRouter));

        // // Deploy ERC20Adaptor
        // creationCode = type(ERC20Adaptor).creationCode;
        // constructorArgs = hex"";
        // erc20Adaptor = ERC20Adaptor(
        //     deployer.deployContract("Test ERC20 Adaptor V0.0", creationCode, constructorArgs, 0)
        // );
        // // Deploy UniswapAdaptor
        // creationCode = type(UniswapV3PositionTracker).creationCode;
        // constructorArgs = abi.encode(uniPositionManager);
        // uniswapV3PositionTracker = UniswapV3PositionTracker(
        //     deployer.deployContract("Test Uniswap Position Tracker V0.0", creationCode, constructorArgs, 0)
        // );
        // creationCode = type(UniswapV3Adaptor).creationCode;
        // constructorArgs = abi.encode(uniPositionManager, address(uniswapV3PositionTracker));
        // uniswapV3Adaptor = UniswapV3Adaptor(
        //     deployer.deployContract("Test UniswapV3 Adaptor V0.0", creationCode, constructorArgs, 0)
        // );

        // // Deploy SushiswapAdaptor
        // creationCode = type(UniswapV3PositionTracker).creationCode;
        // constructorArgs = abi.encode(sushiPositionManager);
        // sushiswapV3PositionTracker = UniswapV3PositionTracker(
        //     deployer.deployContract("Test Sushiswap Position Tracker V0.0", creationCode, constructorArgs, 0)
        // );
        // creationCode = type(UniswapV3Adaptor).creationCode;
        // constructorArgs = abi.encode(sushiPositionManager, address(sushiswapV3PositionTracker));
        // sushiswapV3Adaptor = UniswapV3Adaptor(
        //     deployer.deployContract("Test SushiswapV3 Adaptor V0.0", creationCode, constructorArgs, 0)
        // );
        // // Deploy Aave AToken Adaptor
        // creationCode = type(AaveV3ATokenAdaptor).creationCode;
        // constructorArgs = abi.encode(aaveV3Pool, aaveV3Oracle, 1.05e18);
        // aaveV3ATokenAdaptor = AaveV3ATokenAdaptor(
        //     deployer.deployContract("Test Aave V3 AToken Adaptor V0.0", creationCode, constructorArgs, 0)
        // );
        // // Deploy Aave Debt Token Adaptor
        // creationCode = type(AaveV3DebtTokenAdaptor).creationCode;
        // constructorArgs = abi.encode(aaveV3Pool, 1.05e18);
        // aaveV3DebtTokenAdaptor = AaveV3DebtTokenAdaptor(
        //     deployer.deployContract("Test Aave V3 DebtToken Adaptor V0.0", creationCode, constructorArgs, 0)
        // );
        // // Deploy 1inch aggregator
        // creationCode = type(OneInchAdaptor).creationCode;
        // constructorArgs = abi.encode(oneInchRouter);
        // oneInchAdaptor = OneInchAdaptor(
        //     deployer.deployContract("Test 1Inch Adaptor V0.0", creationCode, constructorArgs, 0)
        // );
        // // Deploy 0x Aggregator
        // creationCode = type(ZeroXAdaptor).creationCode;
        // constructorArgs = abi.encode(oneInchRouter);
        // zeroXAdaptor = ZeroXAdaptor(deployer.deployContract("Test 0x Adaptor V0.0", creationCode, constructorArgs, 0));

        // // Add assets to the price router
        // PriceRouter.ChainlinkDerivativeStorage memory stor;
        // PriceRouter.AssetSettings memory settings;

        // uint256 ethUsdPrice = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(WETH_USD_FEED));
        // priceRouter.addAsset(WETH, settings, abi.encode(stor), ethUsdPrice);

        // uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(USDC_USD_FEED));
        // priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(USDC_USD_FEED));
        // priceRouter.addAsset(USDCe, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(DAI_USD_FEED));
        // priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(USDT_USD_FEED));
        // priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(FRAX_USD_FEED));
        // priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(WBTC_USD_FEED));
        // priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // stor.inETH = true;

        // price = (ethUsdPrice * uint256(IChainlinkAggregator(WSTETH_ETH_FEED).latestAnswer())) / 1e18;
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(WSTETH_ETH_FEED));
        // priceRouter.addAsset(WSTETH, settings, abi.encode(stor), price);

        // price = (ethUsdPrice * uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer())) / 1e18;
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(CBETH_ETH_FEED));
        // priceRouter.addAsset(cbETH, settings, abi.encode(stor), price);

        // // Trust adaptors
        // registry.trustAdaptor(address(erc20Adaptor));
        // registry.trustAdaptor(address(uniswapV3Adaptor));
        // registry.trustAdaptor(address(sushiswapV3Adaptor));
        // registry.trustAdaptor(address(aaveV3ATokenAdaptor));
        // registry.trustAdaptor(address(aaveV3DebtTokenAdaptor));
        // registry.trustAdaptor(address(oneInchAdaptor));
        // registry.trustAdaptor(address(zeroXAdaptor));
        // // Add positions to the registry
        // registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        // registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        // registry.trustPosition(usdcePosition, address(erc20Adaptor), abi.encode(USDCe));
        // registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));
        // registry.trustPosition(usdtPosition, address(erc20Adaptor), abi.encode(USDT));
        // registry.trustPosition(usdcUsdceUniPosition, address(uniswapV3Adaptor), abi.encode(USDC, USDCe));
        // registry.trustPosition(usdcDaiUniPosition, address(uniswapV3Adaptor), abi.encode(USDC, DAI));
        // registry.trustPosition(usdcUsdtUniPosition, address(uniswapV3Adaptor), abi.encode(USDC, USDT));
        // registry.trustPosition(daiUsdceUniPosition, address(uniswapV3Adaptor), abi.encode(DAI, USDCe));
        // registry.trustPosition(usdtUsdceUniPosition, address(uniswapV3Adaptor), abi.encode(USDT, USDCe));
        // registry.trustPosition(aV3WethPosition, address(aaveV3ATokenAdaptor), abi.encode(aV3WETH));
        // registry.trustPosition(aV3UsdcPosition, address(aaveV3ATokenAdaptor), abi.encode(aV3USDC));
        // registry.trustPosition(aV3UsdcePosition, address(aaveV3ATokenAdaptor), abi.encode(aV3USDCe));
        // registry.trustPosition(aV3DaiPosition, address(aaveV3ATokenAdaptor), abi.encode(aV3DAI));
        // registry.trustPosition(aV3UsdtPosition, address(aaveV3ATokenAdaptor), abi.encode(aV3USDT));
        // registry.trustPosition(dV3WethPosition, address(aaveV3DebtTokenAdaptor), abi.encode(dV3WETH));
        // registry.trustPosition(dV3UsdcPosition, address(aaveV3DebtTokenAdaptor), abi.encode(dV3USDC));
        // registry.trustPosition(dV3UsdcePosition, address(aaveV3DebtTokenAdaptor), abi.encode(dV3USDCe));
        // registry.trustPosition(dV3DaiPosition, address(aaveV3DebtTokenAdaptor), abi.encode(dV3DAI));
        // registry.trustPosition(dV3UsdtPosition, address(aaveV3DebtTokenAdaptor), abi.encode(dV3USDT));

        // registry.trustPosition(usdcUsdceSushiPosition, address(sushiswapV3Adaptor), abi.encode(USDC, USDCe));
        // registry.trustPosition(usdcDaiSushiPosition, address(sushiswapV3Adaptor), abi.encode(USDC, DAI));
        // registry.trustPosition(usdcUsdtSushiPosition, address(sushiswapV3Adaptor), abi.encode(USDC, USDT));
        // registry.trustPosition(daiUsdceSushiPosition, address(sushiswapV3Adaptor), abi.encode(DAI, USDCe));
        // registry.trustPosition(usdtUsdceSushiPosition, address(sushiswapV3Adaptor), abi.encode(USDT, USDCe));

        // // Deploy Cellar.
        // ryUsdCellar = _createCellar("Test Real Yield USD", "TRYUSD", USDCe, usdcePosition, abi.encode(0), 1e6, 0.8e18);
        ryUsdCellar = CellarWithOracleWithBalancerFlashLoans(0xA73B0B48E26E4B8B24CeaD149252cc275deE99A6);

        uint64 heartbeat = 1 days;
        uint64 deviationTrigger = 0.0010e4;
        uint64 gracePeriod = 1 days / 6;
        uint16 observationsToUse = 4;
        uint216 startingAnswer = 1e18;
        uint256 allowedAnswerChangeLower = 0.8e4;
        uint256 allowedAnswerChangeUpper = 10e4;
        _createSharePriceOracle(
            "Test Real Yield USD Share Price Oracle V0.2",
            address(ryUsdCellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            testStrategist,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        vm.stopBroadcast();
    }

    function _createCellar(
        string memory cellarName,
        string memory cellarSymbol,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithOracleWithBalancerFlashLoans) {
        // Approve new cellar to spend assets.
        string memory nameToUse = string.concat(cellarName, " V0.0");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.approve(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithOracleWithBalancerFlashLoans).creationCode;
        constructorArgs = abi.encode(
            dev,
            registry,
            holdingAsset,
            cellarName,
            cellarSymbol,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut,
            type(uint192).max,
            address(vault)
        );

        return
            CellarWithOracleWithBalancerFlashLoans(
                deployer.deployContract(nameToUse, creationCode, constructorArgs, 0)
            );
    }

    function _createSharePriceOracle(
        string memory _name,
        address _target,
        uint64 _heartbeat,
        uint64 _deviationTrigger,
        uint64 _gracePeriod,
        uint16 _observationsToUse,
        address _automationAdmin,
        uint216 _startingAnswer,
        uint256 _allowedAnswerChangeLower,
        uint256 _allowedAnswerChangeUpper
    ) internal returns (ERC4626SharePriceOracle) {
        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(ERC4626SharePriceOracle).creationCode;
        constructorArgs = abi.encode(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            automationRegistryV2,
            automationRegistrarV2,
            _automationAdmin,
            address(LINK),
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        );

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
