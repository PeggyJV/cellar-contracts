// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AxelarProxy } from "src/AxelarProxy.sol";
import { Deployer } from "src/Deployer.sol";

import { AvalancheAddresses } from "test/resources/Avalanche/AvalancheAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Avalanche/production/DeployAxelarProxy.s.sol:DeployAxelarProxyScript --evm-version london --rpc-url $AVALANCHE_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 68000000000 --verify --etherscan-api-key $SNOWTRACE_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployAxelarProxyScript is Script, AvalancheAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    function run() external {
        string memory name = "Axelar Proxy V0.0";
        bytes memory creationCode = type(AxelarProxy).creationCode;
        bytes memory constructorArgs = abi.encode(axelarGateway, axelarSommelierSender);

        vm.startBroadcast();
        deployer.deployContract(name, creationCode, constructorArgs, 0);
        vm.stopBroadcast();
    }
}
