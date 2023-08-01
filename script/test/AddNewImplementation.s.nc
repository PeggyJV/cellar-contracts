// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { TEnv } from "script/test/TEnv.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/AddNewImplementation.s.sol:AddNewImplementationScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
//  TODO might be a good idea for out initialized contracts to make a view function available to see if it is initialized or not.
contract AddNewImplementationScript is Script, TEnv {
    CellarInitializableV2_1 private implementation;

    function run() external {
        vm.startBroadcast();

        // uint32[] memory positions = new uint32[](1);
        // uint32[] memory debtPositions;

        // // TODO this should really just be a vanilla ERC20 position to keep it as simple as possible.
        // // TODO should probs choose WETH as the holding position since that contract is fixed and permissionless.
        // positions[0] = eUsdcPosition;

        // bytes[] memory positionConfigs = new bytes[](1);
        // bytes[] memory debtConfigs;

        // // Deploy cellar using factory.
        // bytes memory initializeCallData = abi.encode(
        //     address(gravityBridge),
        //     registry,
        //     USDC,
        //     "TEST Implementation",
        //     "TEST-I",
        //     abi.encode(
        //         positions,
        //         debtPositions,
        //         positionConfigs,
        //         debtConfigs,
        //         eUsdcPosition,
        //         strategist,
        //         type(uint128).max,
        //         type(uint128).max
        //     )
        // );

        // // Deploy new implementation.
        // implementation = new CellarInitializableV2_1(registry);

        // // Initialize implementation.
        // implementation.initialize(initializeCallData);

        vm.stopBroadcast();
    }
}
