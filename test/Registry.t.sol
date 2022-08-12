// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Registry } from "src/Registry.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RegistryTest is Test {
    Registry public registry;

    address public gravityBridge = vm.addr(1);
    address public swapRouter = vm.addr(2);
    address public priceRouter = vm.addr(3);

    function setUp() external {
        registry = new Registry(gravityBridge, swapRouter, priceRouter);
    }

    // ========================================= INITIALIZATION TEST =========================================

    function testInitialization() external {
        assertEq(registry.getAddress(0), gravityBridge, "Should initialize gravity bridge");
        assertEq(registry.getAddress(1), swapRouter, "Should initialize swap router");
        assertEq(registry.getAddress(2), priceRouter, "Should initialize price router");
        assertEq(registry.nextId(), 3, "Should have incremented ID");
    }

    // ============================================= REGISTER TEST =============================================

    function testRegister() external {
        address newAddress = vm.addr(4);

        uint256 expectedId = registry.nextId();
        registry.register(newAddress);

        assertEq(registry.getAddress(expectedId), newAddress, "Should register address at the expected ID");
        assertEq(registry.nextId(), expectedId + 1, "Should have incremented ID");
    }

    // ============================================= ADDRESS TEST =============================================

    function testSetAddress() external {
        address newAddress = vm.addr(4);

        registry.setAddress(0, newAddress);

        assertEq(registry.getAddress(0), newAddress, "Should set to new address");
    }

    function testSetAddressOfInvalidId() external {
        address newAddress = vm.addr(4);

        vm.expectRevert(abi.encodeWithSelector(Registry.Registry__ContractNotRegistered.selector, 999));
        registry.setAddress(999, newAddress);
    }
}
