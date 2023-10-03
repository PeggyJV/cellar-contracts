// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Deployer } from "src/Deployer.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployVestingContracts.s.sol:DeployVestingContractsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployVestingContractsScript is Script, MainnetAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        vm.startBroadcast();

        // Deploy Vesting Simple Adaptor
        creationCode = type(VestingSimpleAdaptor).creationCode;
        deployer.deployContract("VestingSimpleAdaptor V 1.0", creationCode, constructorArgs, 0);

        // Deploy vesting contracts.
        creationCode = type(VestingSimple).creationCode;
        constructorArgs = abi.encode(GHO, 7 days, 0.01e18);
        deployer.deployContract("VestingSimple GHO 7 days V0.0", creationCode, constructorArgs, 0);

        creationCode = type(VestingSimple).creationCode;
        constructorArgs = abi.encode(SWETH, 30 days, 0.01e18);
        deployer.deployContract("VestingSimple SWETH 30 days V0.0", creationCode, constructorArgs, 0);
        vm.stopBroadcast();
    }
}
