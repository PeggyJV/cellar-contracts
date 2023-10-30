// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";

import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

import { RedstoneEthPriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstoneEthPriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployRedstoneEthExtension.s.sol:DeployRedstoneEthExtensionScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployRedstoneEthExtensionScript is Script, MainnetAddresses {
    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    Deployer public deployer = Deployer(deployerAddress);

    RedstoneEthPriceFeedExtension public redstoneEthPriceFeedExtension;

    function run() external {
        vm.startBroadcast();

        bytes memory creationCode = type(RedstoneEthPriceFeedExtension).creationCode;
        bytes memory constructorArgs = abi.encode(priceRouter, WETH);

        deployer.deployContract("Redstone Eth Price Feed Extension V 0.0", creationCode, constructorArgs, 0);

        vm.stopBroadcast();
    }
}
