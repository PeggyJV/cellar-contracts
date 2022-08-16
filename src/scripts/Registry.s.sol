// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { Registry } from "src/Registry.sol";

contract RegistryScript is Script {
    function run() external {
        vm.startBroadcast();
        Registry registry0 = new Registry(address(0), address(0), address(0));
        Registry registry1 = new Registry(address(registry0), address(registry0), address(registry0));

        vm.stopBroadcast();
    }
}
