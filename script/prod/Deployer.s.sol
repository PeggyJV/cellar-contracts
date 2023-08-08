// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/Deployer.s.sol:DeployerScript --rpc-url $MATIC_RPC_URL  --private-key $DEPLOYER_DEPLOYER_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployerScript is Script {
    Deployer public deployer;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address public sommDeployerDeployer = 0x61bfcdAFA35999FA93C10Ec746589EB93817a8b9;

    function run() external {
        address[] memory deployers = new address[](1);
        deployers[0] = sommDev;

        vm.startBroadcast();

        deployer = new Deployer(sommDeployerDeployer, deployers);

        deployer.transferOwnership(sommDev);

        vm.stopBroadcast();
    }
}
