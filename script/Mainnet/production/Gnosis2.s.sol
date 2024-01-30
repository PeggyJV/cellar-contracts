// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";

import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/Gnosis2.s.sol:Gnosis2Script --rpc-url $MAINNET_RPC_URL --sender $MULTI_SIG --with-gas-price 25000000000`
 */
contract Gnosis2Script is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);
    BalancerStablePoolExtension public balancerStablePoolExtension =
        BalancerStablePoolExtension(0x0C392Fb54499d383C6FDA36c13328fc3044CA496);

    address public balancerAdaptor = 0x2750348A897059C45683d33A1742a3989454F7d6;
    address public auraAdaptor = 0x298d97494c5374e796368bCF15F0290771f6aE99;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    // New positions
    uint32 public rethWeethBalancerPosition = 7_000_002;
    uint32 public rethWeethAuraPosition = 7_500_002;

    uint256 currentPriceOfOneRethWeethBptWith8Decimals = 2_462.9e8;

    function run() external {
        PriceRouter.AssetSettings memory settings;
        BalancerStablePoolExtension.ExtensionStorage memory stor;
        vm.startBroadcast();

        // Add pricing.
        stor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: 0x05ff47afada98a98982113758878f9a8b9fdda0a000000000000000000000645,
            poolDecimals: 18,
            rateProviderDecimals: [uint8(18), 18, 0, 0, 0, 0, 0, 0],
            rateProviders: [
                0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F,
                0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee,
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ],
            underlyingOrConstituent: [
                rETH,
                weETH,
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0))
            ]
        });

        settings = PriceRouter.AssetSettings({
            derivative: EXTENSION_DERIVATIVE,
            source: address(balancerStablePoolExtension)
        });

        priceRouter.addAsset(rETH_weETH, settings, abi.encode(stor), currentPriceOfOneRethWeethBptWith8Decimals);

        // Add Balancer Position.
        registry.trustPosition(rethWeethBalancerPosition, balancerAdaptor, abi.encode(rETH_weETH, rETH_weETH_gauge));

        // Add Aura Position.
        registry.trustPosition(rethWeethAuraPosition, auraAdaptor, abi.encode(aura_reth_weth));

        vm.stopBroadcast();
    }
}
