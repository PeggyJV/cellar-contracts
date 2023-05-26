// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Registry } from "src/Registry.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { ERC20, Cellar, PriceRouter } from "src/base/Cellar.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RegistryTest is Test {
    Registry public registry;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address public gravityBridge = vm.addr(1);
    address public swapRouter = vm.addr(2);
    PriceRouter public priceRouter;

    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    function setUp() external {
        priceRouter = new PriceRouter(registry);
        registry = new Registry(gravityBridge, swapRouter, address(priceRouter));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);
    }

    // ========================================= INITIALIZATION TEST =========================================

    function testInitialization() external {
        assertEq(registry.getAddress(0), gravityBridge, "Should initialize gravity bridge");
        assertEq(registry.getAddress(1), swapRouter, "Should initialize swap router");
        assertEq(registry.getAddress(2), address(priceRouter), "Should initialize price router");
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

        registry.setAddress(1, newAddress);

        assertEq(registry.getAddress(1), newAddress, "Should set to new address");

        // Setting address id Zero should revert unless caller is address id Zero.
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__OnlyCallableByZeroId.selector)));
        registry.setAddress(0, address(this));

        // But it can be set by the current Zero Id.
        vm.prank(gravityBridge);
        registry.setAddress(0, address(this));
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

    function testTrustingAndDistrustingAdaptor() external {
        ERC20Adaptor adaptor = new ERC20Adaptor();

        registry.trustAdaptor(address(adaptor));

        registry.distrustAdaptor(address(adaptor));

        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__IdentifierNotUnique.selector)));
        registry.trustAdaptor(address(adaptor));
    }

    function testTrustingAndDistrustingPosition() external {
        ERC20Adaptor adaptor = new ERC20Adaptor();

        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__AdaptorNotTrusted.selector, address(adaptor))));
        registry.trustPosition(address(adaptor), abi.encode(USDC));

        registry.trustAdaptor(address(adaptor));

        uint32 id = registry.trustPosition(address(adaptor), abi.encode(USDC));

        registry.distrustPosition(id);

        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__InvalidPositionInput.selector)));
        registry.trustPosition(address(adaptor), abi.encode(USDC));
    }

    // ============================================= OWNERSHIP TRANSITION TEST =============================================

    function testTransitioningOwner() external {
        address newOwner = vm.addr(777);
        // Current owner has been misbehaving, so governance wants to kick them out.

        // Governance accidentally passes in zero address for new owner.
        vm.startPrank(gravityBridge);
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__NewOwnerCanNotBeZero.selector)));
        registry.transitionOwner(address(0));
        vm.stopPrank();

        // Governance actually uses the right address.
        vm.prank(gravityBridge);
        registry.transitionOwner(newOwner);

        // Old owner tries to call onlyOwner functions.
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__TransitionPending.selector)));
        registry.setAddress(1, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__TransitionPending.selector)));
        registry.setApprovedForDepositOnBehalf(address(this), true);

        // New owner tries claiming ownership before transition period is over.
        vm.startPrank(newOwner);
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__TransitionPending.selector)));
        registry.completeTransition();
        vm.stopPrank();

        vm.warp(block.timestamp + registry.TRANSITION_PERIOD());

        vm.prank(newOwner);
        registry.completeTransition();

        assertEq(registry.owner(), newOwner, "Registry should be owned by new owner.");

        // New owner renounces ownership.
        vm.prank(newOwner);
        registry.renounceOwnership();

        address doug = vm.addr(13);
        // Governance decides to recover ownership and transfer it to doug.
        vm.prank(gravityBridge);
        registry.transitionOwner(doug);

        // Half way through transition governance learns doug is evil, so they cancel the transition.
        vm.warp(block.timestamp + registry.TRANSITION_PERIOD() / 2);
        vm.prank(gravityBridge);
        registry.cancelTransition();

        // doug still tries to claim ownership.
        vm.warp(block.timestamp + registry.TRANSITION_PERIOD() / 2);
        vm.startPrank(doug);
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__TransitionNotPending.selector)));
        registry.completeTransition();
        vm.stopPrank();

        // Governance accidentally calls cancel transition again, but call reverts.
        vm.startPrank(gravityBridge);
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__TransitionNotPending.selector)));
        registry.cancelTransition();
        vm.stopPrank();

        // Governance finds the best owner and starts the process.
        address bestOwner = vm.addr(7777);
        vm.prank(gravityBridge);
        registry.transitionOwner(bestOwner);

        // New owner waits an extra week.
        vm.warp(block.timestamp + 2 * registry.TRANSITION_PERIOD());

        vm.prank(bestOwner);
        registry.completeTransition();

        assertEq(registry.owner(), bestOwner, "Registry should be owned by best owner.");

        // Governance starts another ownership transfer back to doug.
        vm.prank(gravityBridge);
        registry.transitionOwner(doug);

        vm.warp(block.timestamp + 2 * registry.TRANSITION_PERIOD());

        // Doug still has not completed the transfer, so Governance decides to cancel it.
        vm.prank(gravityBridge);
        registry.cancelTransition();

        // Doug tries completing it.
        vm.startPrank(doug);
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__TransitionNotPending.selector)));
        registry.completeTransition();
        vm.stopPrank();
    }
}
