// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Registry} from "src/Registry.sol";
import {PriceRouter} from "src/modules/price-router/PriceRouter.sol";
import {weEthExtension} from "src/modules/price-router/Extensions/EtherFi/weEthExtension.sol";
import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Math} from "src/utils/Math.sol";
import {IRateProvider} from "src/interfaces/external/EtherFi/IRateProvider.sol";
import {PendleExtension} from "src/modules/price-router/Extensions/Pendle/PendleExtension.sol";
import {
    BalancerStablePoolExtension,
    IVault
} from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import {IChainlinkAggregator} from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Mainnet/production/SetUpArchitecture.s.sol:SetUpArchitectureScript --evm-version london --with-gas-price 60000000000 --slow --broadcast --etherscan-api-key $MAINNET_RPC_URL --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SetUpArchitectureScript is Script, MainnetAddresses {
    using Math for uint256;
    using stdJson for string;

    uint256 public privateKey;
    PriceRouter public priceRouter;
    address public weEthExtensionAddress;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    uint256 expectedWeEthPriceInUsd8Decimals = 4_087e8;
    uint256 expectedEEthPriceInUsd8Decimals = 3_869e8;
    uint256 currentPriceOfOneWethWeethBptWith8Decimals = 3_883e8;
    uint256 currentPriceOfOneRethWeethBptWith8Decimals = 3_883e8;
    uint256 lpPrice = 7_413e8;
    uint256 ptPrice = 3_497e8;
    uint256 ytPrice = 179e8;

    address public devOwner = 0x59bAE9c3d121152B27A2B5a46bD917574Ca18142;
    Registry public registry = Registry(0x37912f4c0F0d916890eBD755BF6d1f0A0e059BbD);
    address public balancerStablePoolExtension = 0xf504B437ed0b8ae134D78D8315308eB6Ce0e79F6;
    address public pendleExtension = 0x8279BE9F54b514d81E3fD23da149e8fBB788e9cf;

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
    }

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(privateKey);
        // Deploy Price Router
        priceRouter = new PriceRouter(devOwner, registry, WETH);

        // Deploy Pricing Extensions.
        weEthExtensionAddress = address(new weEthExtension(priceRouter));

        // Add pricing.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(EETH, settings, abi.encode(stor), price);

        stor.inETH = true;
        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        price = priceRouter.getPriceInUSD(WETH); // 8 decimals

        // Add weETH.
        uint256 weEthToEEthConversion = IRateProvider(address(WEETH)).getRate(); // [weETH / eETH]

        price = price.mulDivDown(weEthToEEthConversion, 10 ** WEETH.decimals());

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, weEthExtensionAddress);
        priceRouter.addAsset(WEETH, settings, hex"", price);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, pendleExtension);
        PendleExtension.ExtensionStorage memory pstor =
            PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.LP, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleWeETHMarket), settings, abi.encode(pstor), lpPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.SY, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleWeethSy), settings, abi.encode(pstor), priceRouter.getPriceInUSD(WEETH));

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.PT, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethPt), settings, abi.encode(pstor), ptPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.YT, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethYt), settings, abi.encode(pstor), ytPrice);

        BalancerStablePoolExtension.ExtensionStorage memory bstor;

        bstor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: 0xb9debddf1d894c79d2b2d09f819ff9b856fca55200000000000000000000062a,
            poolDecimals: 18,
            rateProviderDecimals: [uint8(0), 18, 0, 0, 0, 0, 0, 0],
            rateProviders: [
                address(0),
                address(WEETH),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ],
            underlyingOrConstituent: [
                WETH,
                WEETH,
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0))
            ]
        });

        settings = PriceRouter.AssetSettings({derivative: EXTENSION_DERIVATIVE, source: balancerStablePoolExtension});

        priceRouter.addAsset(wEth_weETH_bpt, settings, abi.encode(bstor), currentPriceOfOneWethWeethBptWith8Decimals);

        bstor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: 0x05ff47afada98a98982113758878f9a8b9fdda0a000000000000000000000645,
            poolDecimals: 18,
            rateProviderDecimals: [uint8(18), 18, 0, 0, 0, 0, 0, 0],
            rateProviders: [
                rethRateProvider,
                address(WEETH),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ],
            underlyingOrConstituent: [
                rETH,
                WEETH,
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0))
            ]
        });

        settings = PriceRouter.AssetSettings({derivative: EXTENSION_DERIVATIVE, source: balancerStablePoolExtension});

        priceRouter.addAsset(rETH_weETH_bpt, settings, abi.encode(bstor), currentPriceOfOneRethWeethBptWith8Decimals);

        vm.stopBroadcast();
    }
}
