// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/DeployETHxVesting.s.sol:DeployETHxVestingScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 */
contract DeployETHxVestingScript is Script, MainnetAddresses {
    using Math for uint256;

    Deployer public deployer = Deployer(deployerAddress);

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast();

        creationCode = type(VestingSimple).creationCode;
        constructorArgs = abi.encode(ETHX, 30 days, 0.01e18);
        deployer.deployContract("VestingSimple ETHX 30 days V0.0", creationCode, constructorArgs, 0);

        vm.stopBroadcast();
    }
}
