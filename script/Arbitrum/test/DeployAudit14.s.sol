// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";

import { WithdrawQueue } from "src/modules/withdraw-queue/WithdrawQueue.sol";
import { SimpleSolver } from "src/modules/withdraw-queue/SimpleSolver.sol";

import { SimpleSlippageRouter } from "src/modules/SimpleSlippageRouter.sol";

import "forge-std/Script.sol";

import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddresses.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Arbitrum/test/DeployAudit14.s.sol:DeployAudit14Script --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 100000000 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployAudit14Script is Script, ArbitrumAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        vm.startBroadcast();

        // Deploy SimpleSlippageRouter
        creationCode = type(SimpleSlippageRouter).creationCode;
        // constructorArgs empty
        deployer.deployContract("Test SimpleSlippageRouter V0.1", creationCode, constructorArgs, 0);

        // Deploy Withdraw Queue
        creationCode = type(WithdrawQueue).creationCode;
        // constructorArgs empty
        address queue = deployer.deployContract("Test WithdrawQueue V0.1", creationCode, constructorArgs, 0);

        // Deploy SimpleSolver
        creationCode = type(SimpleSolver).creationCode;
        constructorArgs = abi.encode(queue);
        deployer.deployContract("Test SimpleSolver V0.1", creationCode, constructorArgs, 0);

        vm.stopBroadcast();
    }
}
