// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RedstoneEthPriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstoneEthPriceFeedExtension.sol";
import { MockRedstoneClassicAdapter } from "src/mocks/MockRedstoneClassicAdapter.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract RedstoneEthPriceFeedExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    RedstoneEthPriceFeedExtension private redstoneEthPriceFeedExtension;
    MockRedstoneClassicAdapter private mockRedstoneClassicAdapter;

    IRedstoneAdapter private swEthRedstoneAdapter = IRedstoneAdapter(0x68ba9602B2AeE30847412109D2eE89063bf08Ec2);

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18342280;

        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockRedstoneClassicAdapter = new MockRedstoneClassicAdapter();
        redstoneEthPriceFeedExtension = new RedstoneEthPriceFeedExtension(priceRouter, address(WETH));
    }

    // ======================================= HAPPY PATH =======================================
    function testRedstoneEthPriceFeedExtension() external {
        _addWethToPriceRouter();
        // Setup mock contract to price SWETH, and WSTETH.
        bytes32 swethDataFeedId = bytes32("SWETH");
        bytes32 wstethDataFeedId = bytes32("WSTETH");

        uint256 swethEthPrice = 1.01e18;
        uint256 wstethEthPrice = 1.14e18;

        mockRedstoneClassicAdapter.setValueForDataFeed(swethDataFeedId, swethEthPrice.changeDecimals(18, 8));
        mockRedstoneClassicAdapter.setValueForDataFeed(wstethDataFeedId, wstethEthPrice.changeDecimals(18, 8));
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstoneEthPriceFeedExtension));

        RedstoneEthPriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = swethDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        uint256 expectedSwethPrice = swethEthPrice.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), expectedSwethPrice);

        stor.dataFeedId = wstethDataFeedId;
        uint256 expectedWstethPrice = wstethEthPrice.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        priceRouter.addAsset(WSTETH, settings, abi.encode(stor), expectedWstethPrice);

        // Now try pricing SWETH, and WSTETH in terms of WETH.
        assertApproxEqRel(
            priceRouter.getValue(SWETH, 1e18, WETH),
            swethEthPrice,
            0.001e18,
            "SWETH price should approximately equal 1.01 WETH."
        );
        assertApproxEqRel(
            priceRouter.getValue(WSTETH, 1e18, WETH),
            wstethEthPrice,
            0.001e18,
            "WSTETH price should approximately equal 1.14 WETH."
        );
    }

    function testUsingActualSwethEthFeed() external {
        _addWethToPriceRouter();
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstoneEthPriceFeedExtension));
        uint256 swethEthPrice = 1e18;

        RedstoneEthPriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = swEthEthDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(swEthAdapter);

        uint256 expectedSwethPrice = swethEthPrice.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), expectedSwethPrice);
    }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithStalePrice() external {
        _addWethToPriceRouter();
        bytes32 swethDataFeedId = bytes32("SWETH");
        uint256 swethEthPrice = 1.01e18;

        mockRedstoneClassicAdapter.setValueForDataFeed(swethDataFeedId, swethEthPrice.changeDecimals(18, 8));
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp - 2 days));

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstoneEthPriceFeedExtension));

        RedstoneEthPriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = swethDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        uint256 expectedSwethPrice = swethEthPrice.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    RedstoneEthPriceFeedExtension.RedstoneEthPriceFeedExtension__STALE_PRICE.selector
                )
            )
        );
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), expectedSwethPrice);

        // Update timestamp so price is no longer stale.
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));

        // Asset can be added now.
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), expectedSwethPrice);

        // But if price becomes stale again, pricing calls revert.
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp - 2 days));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    RedstoneEthPriceFeedExtension.RedstoneEthPriceFeedExtension__STALE_PRICE.selector
                )
            )
        );
        priceRouter.getValue(SWETH, 1e18, WETH);
    }

    function testUsingExtensionWithZeroPrice() external {
        _addWethToPriceRouter();
        bytes32 swethDataFeedId = bytes32("SWETH");
        uint256 swethEthPrice = 1.01e18;

        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstoneEthPriceFeedExtension));

        RedstoneEthPriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = swethDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        uint256 expectedSwethPrice = swethEthPrice.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(RedstoneEthPriceFeedExtension.RedstoneEthPriceFeedExtension__ZERO_PRICE.selector)
            )
        );
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), expectedSwethPrice);

        // Update price to non-zero value.
        mockRedstoneClassicAdapter.setValueForDataFeed(swethDataFeedId, 1.01e8);

        // Asset can be added now.
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), expectedSwethPrice);

        // But if price becomes zero again, pricing calls revert.
        mockRedstoneClassicAdapter.setValueForDataFeed(swethDataFeedId, 0);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(RedstoneEthPriceFeedExtension.RedstoneEthPriceFeedExtension__ZERO_PRICE.selector)
            )
        );
        priceRouter.getValue(SWETH, 1e18, WETH);
    }

    function testUsingExtensionWithWrongDataFeedId() external {
        _addWethToPriceRouter();
        // Setup mock contract to price DAI, but NOT USDT.
        bytes32 swethDataFeedId = bytes32("SWETH");
        bytes32 wstethDataFeedId = bytes32("WSTETH");
        uint256 swethEthPrice = 1.01e18;

        mockRedstoneClassicAdapter.setValueForDataFeed(swethDataFeedId, swethEthPrice.changeDecimals(18, 8));
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstoneEthPriceFeedExtension));

        RedstoneEthPriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = wstethDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        uint256 expectedSwethPrice = swethEthPrice.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(RedstoneEthPriceFeedExtension.RedstoneEthPriceFeedExtension__ZERO_PRICE.selector)
            )
        );
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), expectedSwethPrice);

        // Updating to use the correct dataFeedId works.
        stor.dataFeedId = swethDataFeedId;
        priceRouter.addAsset(WSTETH, settings, abi.encode(stor), expectedSwethPrice);
    }

    function testUsingExtensionWithoutPriceRouterSupportingWETH() external {
        bytes32 swethDataFeedId = bytes32("SWETH");
        uint256 swethEthPrice = 1.01e18;

        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));
        mockRedstoneClassicAdapter.setValueForDataFeed(swethDataFeedId, swethEthPrice.changeDecimals(18, 8));

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstoneEthPriceFeedExtension));

        RedstoneEthPriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = swethDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    RedstoneEthPriceFeedExtension.RedstoneEthPriceFeedExtension_WETH_NOT_SUPPORTED.selector
                )
            )
        );
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), 0);

        // Now add WETH to the price router.
        _addWethToPriceRouter();

        uint256 expectedSwethPrice = swethEthPrice.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);

        // Asset can be added now.
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), expectedSwethPrice);
    }

    function _addWethToPriceRouter() internal {
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);
    }
}
