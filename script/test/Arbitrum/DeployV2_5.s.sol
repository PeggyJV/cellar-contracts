// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";
import { ArbitrumAddresses } from "test/resources/ArbitrumAddresses.sol";
import { Deployer } from "src/Deployer.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

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
 *      `source .env && forge script script/test/Arbitrum/DeployV2_5.s.sol:DeployV2_5Script --rpc-url $ARBITRUM_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployV2_5Script is Script, ArbitrumAddresses {
    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    Registry public registry;
    PriceRouter public priceRouter;

    ERC20Adaptor public erc20Adaptor;
    UniswapV3PositionTracker public uniswapV3PositionTracker;
    UniswapV3Adaptor public uniswapV3Adaptor;
    UniswapV3PositionTracker public sushiswapV3PositionTracker;
    UniswapV3Adaptor public sushiswapV3Adaptor;
    AaveV3ATokenAdaptor public aaveV3ATokenAdaptor;
    AaveV3DebtTokenAdaptor public aaveV3DebtTokenAdaptor;
    OneInchAdaptor public oneInchAdaptor;
    ZeroXAdaptor public zeroXAdaptor;

    function run() external {
        Deployer deployer = Deployer(deployerAddress);
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast();

        // Deploy registry.
        creationCode = type(Registry).creationCode;
        constructorArgs = abi.encode(dev, dev, dev, dev);
        registry = Registry(deployer.deployContract("Test Registry V0.0", creationCode, constructorArgs, 0));

        // Deploy price router.
        creationCode = type(PriceRouter).creationCode;
        constructorArgs = abi.encode(dev, registry, WETH);
        priceRouter = PriceRouter(deployer.deployContract("Test PriceRouter V0.0", creationCode, constructorArgs, 0));

        // Update price router in registry.
        registry.setAddress(2, address(priceRouter));

        // Deploy ERC20Adaptor
        creationCode = type(ERC20Adaptor).creationCode;
        constructorArgs = hex"";
        erc20Adaptor = ERC20Adaptor(
            deployer.deployContract("Test ERC20 Adaptor V0.0", creationCode, constructorArgs, 0)
        );
        // Deploy UniswapAdaptor
        creationCode = type(UniswapV3PositionTracker).creationCode;
        constructorArgs = abi.encode(uniPositionManager);
        uniswapV3PositionTracker = UniswapV3PositionTracker(
            deployer.deployContract("Test Uniswap Position Tracker V0.0", creationCode, constructorArgs, 0)
        );
        creationCode = type(UniswapV3Adaptor).creationCode;
        constructorArgs = abi.encode(uniPositionManager, address(uniswapV3PositionTracker));
        uniswapV3Adaptor = UniswapV3Adaptor(
            deployer.deployContract("Test UniswapV3 Adaptor V0.0", creationCode, constructorArgs, 0)
        );

        // Deploy SushiswapAdaptor
        creationCode = type(UniswapV3PositionTracker).creationCode;
        constructorArgs = abi.encode(sushiPositionManager);
        sushiswapV3PositionTracker = UniswapV3PositionTracker(
            deployer.deployContract("Test Sushiswap Position Tracker V0.0", creationCode, constructorArgs, 0)
        );
        creationCode = type(UniswapV3Adaptor).creationCode;
        constructorArgs = abi.encode(sushiPositionManager, address(sushiswapV3PositionTracker));
        sushiswapV3Adaptor = UniswapV3Adaptor(
            deployer.deployContract("Test SushiswapV3 Adaptor V0.0", creationCode, constructorArgs, 0)
        );
        // Deploy Aave AToken Adaptor
        creationCode = type(AaveV3ATokenAdaptor).creationCode;
        constructorArgs = abi.encode(aaveV3Pool, aaveV3Oracle, 1.05e18);
        aaveV3ATokenAdaptor = AaveV3ATokenAdaptor(
            deployer.deployContract("Test Aave V3 AToken Adaptor V0.0", creationCode, constructorArgs, 0)
        );
        // Deploy Aave Debt Token Adaptor
        creationCode = type(AaveV3DebtTokenAdaptor).creationCode;
        constructorArgs = abi.encode(aaveV3Pool, 1.05e18);
        aaveV3DebtTokenAdaptor = AaveV3DebtTokenAdaptor(
            deployer.deployContract("Test Aave V3 DebtToken Adaptor V0.0", creationCode, constructorArgs, 0)
        );
        // Deploy 1inch aggregator
        creationCode = type(OneInchAdaptor).creationCode;
        constructorArgs = abi.encode(oneInchRouter);
        oneInchAdaptor = OneInchAdaptor(
            deployer.deployContract("Test 1Inch Adaptor V0.0", creationCode, constructorArgs, 0)
        );
        // Deploy 0x Aggregator
        creationCode = type(ZeroXAdaptor).creationCode;
        constructorArgs = abi.encode(oneInchRouter);
        zeroXAdaptor = ZeroXAdaptor(deployer.deployContract("Test 0x Adaptor V0.0", creationCode, constructorArgs, 0));

        // Add assets to the price router
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 ethUsdPrice = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(WETH_USD_FEED));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), ethUsdPrice);

        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(USDC_USD_FEED));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(USDC_USD_FEED));
        priceRouter.addAsset(USDCe, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(DAI_USD_FEED));
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(USDT_USD_FEED));
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(FRAX_USD_FEED));
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(WBTC_USD_FEED));
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        stor.inETH = true;

        price = (ethUsdPrice * uint256(IChainlinkAggregator(WSTETH_ETH_FEED).latestAnswer())) / 1e18;
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(WSTETH_ETH_FEED));
        priceRouter.addAsset(WSTETH, settings, abi.encode(stor), price);

        price = (ethUsdPrice * uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer())) / 1e18;
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(CBETH_ETH_FEED));
        priceRouter.addAsset(cbETH, settings, abi.encode(stor), price);

        // Add positions to the registry

        // Deploy Cellar.

        vm.stopBroadcast();
    }
}
