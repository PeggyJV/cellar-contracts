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
 *  source .env && forge script script/Mainnet/production/PeggedPriceRouter.s.sol:PeggedPriceRouterScript --with-gas-price 30000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract PeggedPriceRouterScript is Script, MainnetAddresses {
    using Math for uint256;
    using stdJson for string;

    uint256 public privateKey;
    PriceRouter public priceRouter = PriceRouter(0x693799805B502264f9365440B93C113D86a4fFF5);
    address public weEthExtensionAddress = 0x78E59309bA2779A5D3522E965Fe9Be2790Fd7535;
    address public pendleExtension = 0x7D43A81e32A2c69e0b8457C815E811Ebe8463E56;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    uint256 lpPrice = 7_062e8;
    uint256 ptPrice = 3_295e8;
    uint256 ytPrice = 241e8;
    uint256 currentPriceOfOneWethWeethBptWith8Decimals = 3_613e8;
    uint256 currentPriceOfOneRethWeethBptWith8Decimals = 3_553e8;

    address public devOwner = 0x59bAE9c3d121152B27A2B5a46bD917574Ca18142;
    Registry public registry = Registry(0x37912f4c0F0d916890eBD755BF6d1f0A0e059BbD);
    address public balancerStablePoolExtension = 0x7EdBa5c3796f47f6b6263eD307206ED2496Bd79C;

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
    }

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(privateKey);
        // Deploy Price Router
        // Add pricing.
        // PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        PendleExtension.ExtensionStorage memory pstor =
            PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.YT, pendleWeETHMarket, 300, EETH);
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
