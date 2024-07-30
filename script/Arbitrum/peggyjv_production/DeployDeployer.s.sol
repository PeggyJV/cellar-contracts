// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";

import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddressesPeggyJV.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *       source .env && forge script script/Arbitrum/peggyjv_production/DeployDeployer.s.sol:DeployDeployerScript --evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200

 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployDeployerScript is Script, ArbitrumAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    function run() external {
        address[] memory deployers = new address[](2);
        deployers[0] = dev0Address;

        vm.startBroadcast();
        new Deployer(dev0Address, deployers);
        deployer.transferOwnership(dev0Address);
        vm.stopBroadcast();
    }
}
