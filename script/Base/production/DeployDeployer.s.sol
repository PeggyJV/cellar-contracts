// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";

import { BaseAddresses } from "test/resources/Base/BaseAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Base/production/DeployDeployer.s.sol:DeployDeployerScript --evm-version london --rpc-url $BASE_RPC_URL  --private-key $DEPLOYER_DEPLOYER_KEY —optimize —optimizer-runs 200 --with-gas-price 8612736 --verify --etherscan-api-key $BASESCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployDeployerScript is Script, BaseAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    function run() external {
        address[] memory deployers = new address[](2);
        deployers[0] = dev0Address;
        deployers[1] = dev1Address;

        vm.startBroadcast();
        new Deployer(deployerDeployerAddress, deployers);
        deployer.transferOwnership(dev0Address);
        vm.stopBroadcast();
    }
}
