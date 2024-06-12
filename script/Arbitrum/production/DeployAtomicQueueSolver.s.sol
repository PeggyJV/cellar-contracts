// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/Deployer.sol";
import {AtomicSolverV2} from "src/modules/atomic-queue/AtomicSolverV2.sol";
import {ArbitrumAddresses} from "test/resources/Arbitrum/ArbitrumAddresses.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Arbitrum/production/DeployAtomicQueueSolver.s.sol:DeployAtomicQueueSolverScript --evm-version london --with-gas-price 100000000 --slow --broadcast
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployAtomicQueueSolverScript is Script, ArbitrumAddresses {
    uint256 public privateKey;
    Deployer public deployer = Deployer(deployerAddress);

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast(privateKey);

        creationCode = type(AtomicSolverV2).creationCode;
        constructorArgs = abi.encode(devStrategist, vault);
        deployer.deployContract("Nothing to see here V 0.0", creationCode, constructorArgs, 0);

        vm.stopBroadcast();
    }
}
