// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

import { RedstoneEthPriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstoneEthPriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/Gnosis5.s.sol:Gnosis5Script --rpc-url $MAINNET_RPC_URL --sender $MULTI_SIG --with-gas-price 25000000000`
 */
contract Gnosis5Script is Script, MainnetAddresses {
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    uint256 ethXPriceUsdWith8Decimals = 2_315e8;

    function run() external {
        // Use SWETHs settings.
        PriceRouter.AssetSettings memory settings;
        (settings.derivative, settings.source) = priceRouter.getAssetSettings(SWETH);
        RedstoneEthPriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = ethXEthDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(ethXAdapter);

        vm.startBroadcast();

        priceRouter.addAsset(ETHX, settings, abi.encode(stor), ethXPriceUsdWith8Decimals);

        vm.stopBroadcast();
    }
}
