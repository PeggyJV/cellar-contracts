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

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/Gnosis8.s.sol:Gnosis8Script --rpc-url $MAINNET_RPC_URL --sender $MULTI_SIG --with-gas-price 25000000000`
 */
contract Gnosis8Script is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    address public balancerAdaptor = 0x2750348A897059C45683d33A1742a3989454F7d6;
    address public auraAdaptor = 0x298d97494c5374e796368bCF15F0290771f6aE99;
    address public curveAdaptor = 0x94E28529f73dAD189CD0bf9D83a06572d4bFB26a;
    address public convexCurveAdaptor = 0x98C44FF447c62364E3750C5e2eF8acc38391A8B0;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    // New positions
    uint32 public rethWethBalancerPosition = 7_000_003;
    uint32 public rethWethAuraPosition = 7_500_003;

    function run() external {
        PriceRouter.AssetSettings memory settings;
        (settings.derivative, settings.source) = priceRouter.getAssetSettings(WETH);
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        (stor.max, stor.min, stor.heartbeat, stor.inETH) = priceRouter.getChainlinkDerivativeStorage(WETH);
        vm.startBroadcast();

        priceRouter.startEditAsset(STETH, settings, abi.encode(stor));

        vm.stopBroadcast();
    }
}
