// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

import { WithdrawQueue } from "src/modules/withdraw-queue/WithdrawQueue.sol";
import { SimpleSolver } from "src/modules/withdraw-queue/SimpleSolver.sol";

import { Curve2PoolExtension } from "src/modules/price-router/Extensions/Curve/Curve2PoolExtension.sol";
import { CurveEMAExtension } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";

import { SimpleSlippageRouter } from "src/modules/SimpleSlippageRouter.sol";

import "forge-std/Script.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/prod/DeployAudit14.s.sol:DeployAudit14Script --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployAudit14Script is Script, MainnetAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        vm.startBroadcast();

        // // Deploy SimpleSlippageRouter
        // creationCode = type(SimpleSlippageRouter).creationCode;
        // // constructorArgs empty
        // deployer.deployContract("SimpleSlippageRouter V0.0", creationCode, constructorArgs, 0);

        // // Deploy Withdraw Queue
        // creationCode = type(WithdrawQueue).creationCode;
        // // constructorArgs empty
        // address queue = deployer.deployContract("WithdrawQueue V0.0", creationCode, constructorArgs, 0);

        // // Deploy SimpleSolver
        // creationCode = type(SimpleSolver).creationCode;
        // constructorArgs = abi.encode(queue);
        // deployer.deployContract("SimpleSolver V0.0", creationCode, constructorArgs, 0);

        // Deploy Curve2PoolExtension
        creationCode = type(Curve2PoolExtension).creationCode;
        constructorArgs = abi.encode(priceRouter, WETH, 18);
        deployer.deployContract("Curve2PoolExtension V0.0", creationCode, constructorArgs, 0);

        // Deploy CurveEMAExtension
        creationCode = type(CurveEMAExtension).creationCode;
        constructorArgs = abi.encode(priceRouter, WETH, 18);
        deployer.deployContract("CurveEMAExtension V0.0", creationCode, constructorArgs, 0);

        vm.stopBroadcast();
    }
}
