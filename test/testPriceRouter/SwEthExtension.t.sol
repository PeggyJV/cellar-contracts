// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {SwEthExtension} from "src/modules/price-router/Extensions/Swell/SwEthExtension.sol";
import {IRateProvider} from "src/interfaces/external/EtherFi/IRateProvider.sol";
import {AdaptorHelperFunctions} from "test/resources/AdaptorHelperFunctions.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

// Pinned after Redstone's swETH adapter went stale, so the live-router test below
// exercises the actual outage this extension replaces.
uint256 constant SWETH_TEST_FORK_BLOCK = 26007554;

contract SwEthExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;

    SwEthExtension private swethExtension;

    function setUp() external {
        _startFork("MAINNET_RPC_URL", SWETH_TEST_FORK_BLOCK);
        _setUp();
        swethExtension = new SwEthExtension(priceRouter);
    }

    // ======================================= HAPPY PATH =======================================
    function testAddSwEthExtension() external {
        _addWeth();

        // swETH reports its own ETH value per token, 18 decimals.
        uint256 rate = IRateProvider(address(SWETH)).getRate();
        uint256 price = priceRouter.getPriceInUSD(WETH).mulDivDown(rate, 10 ** SWETH.decimals());

        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
            EXTENSION_DERIVATIVE,
            address(swethExtension)
        );
        priceRouter.addAsset(SWETH, settings, abi.encode(0), price);

        assertApproxEqRel(
            priceRouter.getValue(SWETH, 1e18, WETH),
            rate,
            1e8,
            "1 swETH should be worth getRate() WETH."
        );
    }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithWrongAsset() external {
        _addWeth();

        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
            EXTENSION_DERIVATIVE,
            address(swethExtension)
        );

        address notSwEth = vm.addr(123);
        vm.expectRevert(bytes(abi.encodeWithSelector(SwEthExtension.SwEthExtension__ASSET_NOT_SWETH.selector)));
        priceRouter.addAsset(ERC20(notSwEth), settings, abi.encode(0), 1e8);
    }

    function testAddingSwEthWithoutPricingWeth() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
            EXTENSION_DERIVATIVE,
            address(swethExtension)
        );

        vm.expectRevert(bytes(abi.encodeWithSelector(SwEthExtension.SwEthExtension__WETH_NOT_SUPPORTED.selector)));
        priceRouter.addAsset(SWETH, settings, abi.encode(0), 1e8);
    }

    function _addWeth() internal {
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        priceRouter.addAsset(
            WETH,
            PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED),
            abi.encode(stor),
            price
        );
    }
}

/// @notice Exercises the extension against the live PriceRouter rather than a fresh one,
///         through the same owner-only, timelocked edit the Safe will execute.
contract SwEthExtensionLiveRouterTest is Test {
    using Math for uint256;

    PriceRouter private constant LIVE_ROUTER = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);
    address private constant ROUTER_OWNER = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private constant TURBO_SWETH = 0xd33dAd974b938744dAC81fE00ac67cb5AA13958E;
    ERC20 private constant SWETH = ERC20(0xf951E335afb289353dc249e82926178EaC7DEd78);
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    uint8 private constant EXTENSION_DERIVATIVE = 3;

    /// @dev PriceRouter.assetEditableTimestamp, confirmed against the deployed contract.
    uint256 private constant EDIT_TIMESTAMP_SLOT = 4;

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), SWETH_TEST_FORK_BLOCK);
    }

    function testRepointingSwEthUnfreezesTurboSwEth() external {
        // Precondition: the vault cannot be valued while swETH prices through Redstone.
        (bool okBefore, ) = TURBO_SWETH.staticcall(abi.encodeWithSignature("totalAssets()"));
        assertFalse(okBefore, "Turbo swETH should be frozen before the edit.");

        SwEthExtension extension = new SwEthExtension(LIVE_ROUTER);
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(extension));
        bytes memory stor = "";

        vm.startPrank(ROUTER_OWNER);
        LIVE_ROUTER.startEditAsset(SWETH, settings, stor);

        // Simulate the 7-day timelock by making the edit due now. Warping instead would
        // leave the live WETH/USD feed stale and fail for the wrong reason.
        bytes32 editHash = keccak256(abi.encode(SWETH, settings, stor));
        bytes32 slot = keccak256(abi.encode(editHash, EDIT_TIMESTAMP_SLOT));
        assertEq(
            uint256(vm.load(address(LIVE_ROUTER), slot)),
            block.timestamp + 7 days,
            "edit not timelocked as expected"
        );
        vm.store(address(LIVE_ROUTER), slot, bytes32(block.timestamp));

        uint256 expected = LIVE_ROUTER.getPriceInUSD(WETH).mulDivDown(
            IRateProvider(address(SWETH)).getRate(),
            10 ** SWETH.decimals()
        );
        LIVE_ROUTER.completeEditAsset(SWETH, settings, stor, expected);
        vm.stopPrank();

        assertEq(LIVE_ROUTER.getPriceInUSD(SWETH), expected, "router should price swETH from its own rate");

        (bool okAfter, bytes memory ret) = TURBO_SWETH.staticcall(abi.encodeWithSignature("totalAssets()"));
        assertTrue(okAfter, "Turbo swETH should be valued after the edit.");
        uint256 totalAssets = abi.decode(ret, (uint256));
        // ~2.26 WETH was measured independently on a fork before this contract existed.
        assertApproxEqRel(totalAssets, 2.264e18, 0.02e18, "Turbo swETH total assets out of expected range.");
    }
}
