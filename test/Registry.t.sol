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
        priceRouter = new PriceRouter();
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
}
