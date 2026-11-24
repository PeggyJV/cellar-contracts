// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test } from "@forge-std/Test.sol";
import { MorphoTreasuryAdaptor } from "src/modules/adaptors/Morpho/MorphoTreasuryAdaptor.sol";

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
}

interface ICellarLike {
    struct AdaptorCall {
        address adaptor;
        bytes[] callData;
    }

    function totalAssets() external view returns (uint256);
    function addAdaptorToCatalogue(address adaptor) external;
    function setupAdaptor(address adaptor) external;
    function callOnAdaptor(AdaptorCall[] memory data) external;
    function multicall(bytes[] calldata data) external;
}

interface IRegistryLike {
    function trustAdaptor(address adaptor) external;
    function trustAdaptor(address adaptor, uint128 assetRisk, uint128 protocolRisk) external;
}

/// @notice Mainnet-fork tests against the live cellars that hold Legacy MORPHO from Morpho Optimizer rewards.
contract MorphoTreasuryAdaptorTest is Test {
    address private constant GRAVITY = 0x69592e6f9d21989a043646fE8225da2600e5A0f7; // owner of every cellar below
    address private constant REGISTRY_OWNER_SAFE = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private constant RYUSD_REGISTRY_TIMELOCK = 0xaDa78a5E01325B91Bc7879a63c309F7D54d42950;

    address private constant REGISTRY_V2_5 = 0xEED68C267E9313a6ED6ee08de08c9F68dee44476;
    address private constant REGISTRY_RYBTC_RYETH = 0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08;
    address private constant REGISTRY_RYUSD = 0x2Cbd27E034FEE53f79b607430dA7771B22050741;

    address private constant REAL_YIELD_BTC = 0x0274a704a6D9129F90A62dDC6f6024b33EcDad36;
    address private constant REAL_YIELD_USD = 0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E;
    address private constant TURBO_EZETH = 0x27500De405a3212D57177A789E30bb88b0AdbeC5;

    MorphoTreasuryAdaptor private adaptor;
    IERC20Like private legacy;
    IERC20Like private morpho;
    address private recipient;
    address private wrapper;

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 26487406);
        adaptor = new MorphoTreasuryAdaptor();
        legacy = IERC20Like(address(adaptor.LEGACY_MORPHO()));
        morpho = IERC20Like(address(adaptor.MORPHO()));
        recipient = adaptor.RECIPIENT();
        wrapper = address(adaptor.WRAPPER());
    }

    function testConstants() external {
        assertEq(address(legacy), 0x9994E35Db50125E0DF82e4c2dde62496CE330999);
        assertEq(address(morpho), 0x58D97B57BB95320F9a05dC918Aef65434969c2B2);
        assertEq(wrapper, 0x9D03bb2092270648d7480049d0E58d2FcF0E5123);
        assertEq(recipient, 0x7566D348038d881475b5FE0638c00B391f9B33E6);
        assertEq(adaptor.identifier(), keccak256(abi.encode("Morpho Treasury Adaptor V 1.0")));
    }

    function testPositionHooksRevert() external {
        bytes memory empty;
        vm.expectRevert(MorphoTreasuryAdaptor.MorphoTreasuryAdaptor__NotAPosition.selector);
        adaptor.balanceOf(empty);
        vm.expectRevert(MorphoTreasuryAdaptor.MorphoTreasuryAdaptor__NotAPosition.selector);
        adaptor.assetOf(empty);
        vm.expectRevert(MorphoTreasuryAdaptor.MorphoTreasuryAdaptor__NotAPosition.selector);
        adaptor.withdrawableFrom(empty, empty);
        vm.expectRevert(MorphoTreasuryAdaptor.MorphoTreasuryAdaptor__NotAPosition.selector);
        adaptor.deposit(1, empty, empty);
        vm.expectRevert(MorphoTreasuryAdaptor.MorphoTreasuryAdaptor__NotAPosition.selector);
        adaptor.withdraw(1, address(this), empty, empty);
        vm.expectRevert(MorphoTreasuryAdaptor.MorphoTreasuryAdaptor__NotAPosition.selector);
        adaptor.isDebt();
    }

    function testRealYieldBtcWrapsAllLegacyToRecipient() external {
        vm.prank(REGISTRY_OWNER_SAFE);
        IRegistryLike(REGISTRY_RYBTC_RYETH).trustAdaptor(address(adaptor));
        _runViaMulticall(REAL_YIELD_BTC);
    }

    function testTurboEzEthWrapsLegacyAndSweepsCurrentMorpho() external {
        assertGt(morpho.balanceOf(TURBO_EZETH), 0, "expected current MORPHO in cellar");
        vm.prank(REGISTRY_OWNER_SAFE);
        IRegistryLike(REGISTRY_V2_5).trustAdaptor(address(adaptor));
        _runViaMulticall(TURBO_EZETH);
    }

    function testRealYieldUsdOlderCellarWithSetupAdaptor() external {
        // The RYUSD registry is owned by a timelock; this stands in for its delayed execute.
        vm.prank(RYUSD_REGISTRY_TIMELOCK);
        IRegistryLike(REGISTRY_RYUSD).trustAdaptor(address(adaptor), 0, 0);
        vm.prank(GRAVITY);
        ICellarLike(REAL_YIELD_USD).setupAdaptor(address(adaptor));
        (uint256 expected, uint256 totalBefore, uint256 recipientBefore) = _snapshot(REAL_YIELD_USD);
        vm.prank(GRAVITY);
        ICellarLike(REAL_YIELD_USD).callOnAdaptor(_adaptorCalls());
        _check(REAL_YIELD_USD, expected, totalBefore, recipientBefore);
    }

    function testUntrustedAdaptorCannotBeAdded() external {
        vm.prank(GRAVITY);
        vm.expectRevert();
        ICellarLike(REAL_YIELD_BTC).addAdaptorToCatalogue(address(adaptor));
    }

    function _runViaMulticall(address cellar) internal {
        (uint256 expected, uint256 totalBefore, uint256 recipientBefore) = _snapshot(cellar);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(ICellarLike.addAdaptorToCatalogue, (address(adaptor)));
        calls[1] = abi.encodeCall(ICellarLike.callOnAdaptor, (_adaptorCalls()));
        vm.prank(GRAVITY);
        ICellarLike(cellar).multicall(calls);
        _check(cellar, expected, totalBefore, recipientBefore);
    }

    function _adaptorCalls() internal view returns (ICellarLike.AdaptorCall[] memory data) {
        bytes[] memory callData = new bytes[](2);
        callData[0] = abi.encodeCall(MorphoTreasuryAdaptor.wrapLegacyToRecipient, ());
        callData[1] = abi.encodeCall(MorphoTreasuryAdaptor.sweepMorphoToRecipient, ());
        data = new ICellarLike.AdaptorCall[](1);
        data[0] = ICellarLike.AdaptorCall({ adaptor: address(adaptor), callData: callData });
    }

    function _snapshot(address cellar) internal returns (uint256 expected, uint256 totalBefore, uint256 recipientBefore) {
        expected = legacy.balanceOf(cellar) + morpho.balanceOf(cellar);
        assertGt(expected, 0, "cellar holds no MORPHO at fork block");
        totalBefore = ICellarLike(cellar).totalAssets();
        recipientBefore = morpho.balanceOf(recipient);
    }

    function _check(address cellar, uint256 expected, uint256 totalBefore, uint256 recipientBefore) internal {
        assertEq(morpho.balanceOf(recipient) - recipientBefore, expected, "recipient amount");
        assertEq(legacy.balanceOf(cellar), 0, "legacy left in cellar");
        assertEq(morpho.balanceOf(cellar), 0, "MORPHO left in cellar");
        assertEq(legacy.allowance(cellar, wrapper), 0, "wrapper allowance left");
        assertEq(ICellarLike(cellar).totalAssets(), totalBefore, "cellar NAV changed");
    }
}
