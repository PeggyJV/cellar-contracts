// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";

import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddressesPeggyJV.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *       source .env && forge script script/Arbitrum/peggyjv_production/ExampleDeploy/DeployDeployer.s.sol:DeployDeployerScript --evm-version london --rpc-url $ARBITRUM_RPC_URL --with-gas-price 100000000 --broadcast --private-key $PRIVATE_KEY —optimize —optimizer-runs 200
 */
contract DeployDeployerScript is Script, ArbitrumAddresses {

    function run() external {
        address[] memory deployers = new address[](2);
        deployers[0] = dev0Address;

        vm.startBroadcast();

        Deployer deployer = new Deployer(dev0Address, deployers);
        deployer.transferOwnership(dev0Address);
        address deployerAddress = address(deployer);

        vm.stopBroadcast();

        console.log("Deployer deployed at:", deployerAddress);
    }
}
