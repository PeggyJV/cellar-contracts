// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { StEthExtension } from "src/modules/price-router/Extensions/Lido/StEthExtension.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeploySupportingContracts.s.sol:DeploySupportingContractsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeploySupportingContractsScript is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    StEthExtension public stEthExtension;
    WstEthExtension public wstEthExtension;
    RedstonePriceFeedExtension public redstonePriceFeedExtension;
    BalancerStablePoolExtension public balancerStablePoolExtension;

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        vm.startBroadcast();

        // Deploy the price router.
        // creationCode = type(PriceRouter).creationCode;
        // constructorArgs = abi.encode(sommDev, registry, WETH);
        // priceRouter = PriceRouter(deployer.deployContract("PriceRouter V0.0", creationCode, constructorArgs, 0));

        // Deploy stETH extension.
        {
            uint256 _allowedDivergence = 50;
            address _uniV3WstEthWethPool = WSTETH_WETH_100;
            address _stEthToEthDataFeed = STETH_ETH_FEED;
            uint24 _heartbeat = 1 days;
            address _weth = address(WETH);
            address _steth = address(STETH);
            uint32 _twapDuration = 1 days / 4;
            uint128 _minimumMeanLiquidity = 0.5e25;
            creationCode = type(StEthExtension).creationCode;
            constructorArgs = abi.encode(
                priceRouter,
                _allowedDivergence,
                _uniV3WstEthWethPool,
                _stEthToEthDataFeed,
                _heartbeat,
                _weth,
                _steth,
                _twapDuration,
                _minimumMeanLiquidity
            );
            stEthExtension = StEthExtension(
                deployer.deployContract("stETH Extension V0.0", creationCode, constructorArgs, 0)
            );
        }

        // Deploy WSTETH Extension.
        {
            creationCode = type(WstEthExtension).creationCode;
            constructorArgs = abi.encode(priceRouter);
            wstEthExtension = WstEthExtension(
                deployer.deployContract("wstETH Extension V0.0", creationCode, constructorArgs, 0)
            );
        }

        // Deploy redstone extension.
        {
            creationCode = type(RedstonePriceFeedExtension).creationCode;
            constructorArgs = abi.encode(priceRouter);
            redstonePriceFeedExtension = RedstonePriceFeedExtension(
                deployer.deployContract("Redstone Extension V0.0", creationCode, constructorArgs, 0)
            );
        }

        // Add Chainlink USD assets.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(GHO_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, GHO_USD_FEED);
        priceRouter.addAsset(GHO, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(COMP_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, COMP_USD_FEED);
        priceRouter.addAsset(COMP, settings, abi.encode(stor), price);

        // TODO price RYGOV assets.

        // Add Chainlink ETH assets.
        stor.inETH = true;

        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CBETH_ETH_FEED);
        priceRouter.addAsset(cbETH, settings, abi.encode(stor), price);

        // Add stETH
        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(stEthExtension));
        priceRouter.addAsset(STETH, settings, abi.encode(0), price);

        // Add wstEth.
        uint256 wstethToStethConversion = wstEthExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstEthExtension));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);

        // Add swEth.
        RedstonePriceFeedExtension.ExtensionStorage memory redstoneStor;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));
        redstoneStor.dataFeedId = swEthDataFeedId;
        redstoneStor.heartbeat = 1 days;
        redstoneStor.redstoneAdapter = IRedstoneAdapter(swEthAdapter);
        priceRouter.addAsset(SWETH, settings, abi.encode(redstoneStor), 1902e8);

        // Add Balancer Assets.
        // WETH RETH BPT
        uint8[8] memory rateProviderDecimals;
        rateProviderDecimals[1] = 18;
        address[8] memory rateProviders;
        rateProviders[1] = rethRateProvider;
        ERC20[8] memory underlyings;
        underlyings[0] = WETH;
        underlyings[1] = rETH;
        BalancerStablePoolExtension.ExtensionStorage memory balancerStor = BalancerStablePoolExtension
            .ExtensionStorage({
                poolId: bytes32(0),
                poolDecimals: 18,
                rateProviderDecimals: rateProviderDecimals,
                rateProviders: rateProviders,
                underlyingOrConstituent: underlyings
            });

        priceRouter.addAsset(rETH_wETH_BPT, settings, abi.encode(balancerStor), 1915e8);

        // TODO BB A USD
        // TODO GHO BB A USD
        // TODO GHO LUSD
        // TODO WSTETH BB A WETH
        // TODO SWETH BB A WETH
        // TODO WETH cbETH
        // TODO WETH SWETH?????
        // TODO WSTETH WETH BPT????

        vm.stopBroadcast();
    }
}
