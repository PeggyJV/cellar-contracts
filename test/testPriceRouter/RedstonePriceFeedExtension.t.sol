// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Registry } from "src/Registry.sol";

import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { MockRedstoneClassicAdapter } from "src/mocks/MockRedstoneClassicAdapter.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RedstonePriceFeedExtensionTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    PriceRouter private priceRouter;

    RedstonePriceFeedExtension private redstonePriceFeedExtension;
    MockRedstoneClassicAdapter private mockRedstoneClassicAdapter;

    address private immutable sender = vm.addr(0xABCD);
    address private immutable receiver = vm.addr(0xBEEF);

    // Valid Derivatives
    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant TWAP_DERIVATIVE = 2;
    uint8 private constant EXTENSION_DERIVATIVE = 3;

    // Mainnet contracts:
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;

    Registry private registry;

    function setUp() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        registry = new Registry(address(this), address(this), address(this));

        priceRouter = new PriceRouter(registry, WETH);
        mockRedstoneClassicAdapter = new MockRedstoneClassicAdapter();
        redstonePriceFeedExtension = new RedstonePriceFeedExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    // ======================================= HAPPY PATH =======================================
    function testRedstonePriceFeedExtension() external {
        // Setup mock contract to price DAI, and USDT.
        bytes32 daiDataFeedId = bytes32("DAI");
        bytes32 usdtDataFeedId = bytes32("USDT");

        mockRedstoneClassicAdapter.setValueForDataFeed(daiDataFeedId, 1e8);
        mockRedstoneClassicAdapter.setValueForDataFeed(usdtDataFeedId, 1e8);
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));

        RedstonePriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = daiDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        stor.dataFeedId = usdtDataFeedId;
        priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);

        // Now try pricing DAI, and USDT in terms of USDC.
        assertApproxEqRel(
            priceRouter.getValue(DAI, 1e18, USDC),
            1e6,
            0.001e18,
            "DAI price should approximately equal USDC price."
        );
        assertApproxEqRel(
            priceRouter.getValue(USDT, 1e6, USDC),
            1e6,
            0.001e18,
            "USDT price should approximately equal USDC price."
        );
    }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithStalePrice() external {
        // Setup mock contract to price DAI, and USDT.
        bytes32 daiDataFeedId = bytes32("DAI");

        mockRedstoneClassicAdapter.setValueForDataFeed(daiDataFeedId, 1e8);
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp - 2 days));

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));

        RedstonePriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = daiDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        vm.expectRevert(
            bytes(abi.encodeWithSelector(RedstonePriceFeedExtension.RedstonePriceFeedExtension__STALE_PRICE.selector))
        );
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        // Update timestamp so price is no longer stale.
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));

        // Asset can be added now.
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        // But if price becomes stale again, pricing calls revert.
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp - 2 days));
        vm.expectRevert(
            bytes(abi.encodeWithSelector(RedstonePriceFeedExtension.RedstonePriceFeedExtension__STALE_PRICE.selector))
        );
        priceRouter.getValue(DAI, 1e18, USDC);
    }

    function testUsingExtensionWithZeroPrice() external {
        // Setup mock contract to price DAI, and USDT.
        bytes32 daiDataFeedId = bytes32("DAI");

        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));

        RedstonePriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = daiDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        vm.expectRevert(
            bytes(abi.encodeWithSelector(RedstonePriceFeedExtension.RedstonePriceFeedExtension__ZERO_PRICE.selector))
        );
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        // Update price to non-zero value.
        mockRedstoneClassicAdapter.setValueForDataFeed(daiDataFeedId, 1e8);

        // Asset can be added now.
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        // But if price becomes zero again, pricing calls revert.
        mockRedstoneClassicAdapter.setValueForDataFeed(daiDataFeedId, 0);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(RedstonePriceFeedExtension.RedstonePriceFeedExtension__ZERO_PRICE.selector))
        );
        priceRouter.getValue(DAI, 1e18, USDC);
    }

    function testUsingExtensionWithWrongDataFeedId() external {
        // Setup mock contract to price DAI, but NOT USDT.
        bytes32 daiDataFeedId = bytes32("DAI");
        bytes32 usdtDataFeedId = bytes32("USDT");

        mockRedstoneClassicAdapter.setValueForDataFeed(daiDataFeedId, 1e8);
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));

        RedstonePriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = usdtDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        vm.expectRevert(
            bytes(abi.encodeWithSelector(RedstonePriceFeedExtension.RedstonePriceFeedExtension__ZERO_PRICE.selector))
        );
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        // Updating to use the correct dataFeedId works.
        stor.dataFeedId = daiDataFeedId;
        priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);
    }
}
