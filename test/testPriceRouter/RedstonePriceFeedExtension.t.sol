// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { MockRedstoneClassicAdapter } from "src/mocks/MockRedstoneClassicAdapter.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract RedstonePriceFeedExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    RedstonePriceFeedExtension private redstonePriceFeedExtension;
    MockRedstoneClassicAdapter private mockRedstoneClassicAdapter;

    IRedstoneAdapter private swEthRedstoneAdapter = IRedstoneAdapter(0x68ba9602B2AeE30847412109D2eE89063bf08Ec2);

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17735270;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

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

    function testRedstonePriceFeedExtensionSwEth() external {
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));

        RedstonePriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = swEthDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = swEthRedstoneAdapter;
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), 1934e8);

        // Now try pricing swEth in terms of USDC, and WETH.
        assertApproxEqRel(
            priceRouter.getValue(SWETH, 1e18, USDC),
            1934.77e6,
            0.0001e18,
            "swEth price should approximately equal 1,934 USDC."
        );

        assertApproxEqRel(
            priceRouter.getValue(SWETH, 1e18, WETH),
            1.02519e18,
            0.0001e18,
            "swEth price should approximately equal 1.02519 WETH."
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
