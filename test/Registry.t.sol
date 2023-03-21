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

    function testSetApprovedForDepositOnBehalf() external {
        address router = vm.addr(333);
        assertTrue(!registry.approvedForDepositOnBehalf(router), "Router should not be set up as a depositor.");
        // Give approval.
        registry.setApprovedForDepositOnBehalf(router, true);
        assertTrue(registry.approvedForDepositOnBehalf(router), "Router should be set up as a depositor.");

        // Revoke approval.
        registry.setApprovedForDepositOnBehalf(router, false);
        assertTrue(!registry.approvedForDepositOnBehalf(router), "Router should not be set up as a depositor.");
    }

    function testSetFeeDistributor() external {
        bytes32 validCosmosAddress = hex"000000000000000000000000ffffffffffffffffffffffffffffffffffffffff";
        // Try setting an invalid fee distributor.
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__InvalidCosmosAddress.selector)));
        registry.setFeesDistributor(hex"0000000000000000000000010000000000000000000000000000000000000000");

        registry.setFeesDistributor(validCosmosAddress);
        assertEq(registry.feesDistributor(), validCosmosAddress, "Fee distributor should equal `validCosmosAddress`.");
    }

    // TODO add test where
    // adaptor/position is trusted and untrusted, should revert bc something needs to change to re-add it
    // cellar tries to add distrusted position/adaptor to its catalogue
    // cellar tries to use a distrusted position it already has in its catalogue
    // cellar ignores the pause, and continues as normal
    // cellar pause will stop all user interactions, and rebalances
    // scenario where position is found with an exploit
    // scenario where adaptor is found with an exploit
    // re above two but change it so that strategist is cooperating.
}
