// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";

import { BaseAddresses } from "test/resources/Base/BaseAddressesPeggyJV.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *       source .env && forge script script/Base/peggyjv_production/DeployDeployer.s.sol:DeployDeployerScript --evm-version london --rpc-url $BASE_RPC_URL --with-gas-price 100000000 --broadcast --private-key $PRIVATE_KEY —optimize —optimizer-runs 200

 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployDeployerScript is Script, BaseAddresses {

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
