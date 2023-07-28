// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AxelarProxy } from "src/AxelarProxy.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/Arbitrum/DeployProxy.s.sol:DeployProxyScript --rpc-url $ARBITRUM_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployProxyScript is Script {
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    address private gateway = 0xe432150cce91c13a887f7D836923d5597adD8E31;

    string private sourceChain = "Polygon";
    string private sourceAddress = "0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90";

    function run() external {
        vm.startBroadcast();

        AxelarProxy proxy = new AxelarProxy(gateway);

        vm.stopBroadcast();
    }
}
