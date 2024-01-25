// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { eEthExtension } from "src/modules/price-router/Extensions/EtherFi/eETHExtension.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { MockRedstoneClassicAdapter } from "src/mocks/MockRedstoneClassicAdapter.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import { IRateProvider } from "src/interfaces/external/EtherFi/IRateProvider.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

contract eEthExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    RedstonePriceFeedExtension private redstonePriceFeedExtension;
    MockRedstoneClassicAdapter private mockRedstoneClassicAdapter;

    // Deploy the extension.
    eEthExtension private eethExtension;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19085018;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();
    }

    // ======================================= HAPPY PATH =======================================
    function testAddEEthExtension() external {
        // Setup dependent price feeds.
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer()); // [USD / WETH] to be used as a mock for [USD / EETH]
        PriceRouter.AssetSettings memory settings;

        _addDependentPriceFeeds();

        // Add eETH.
        uint256 weEthToEEthConversion = IRateProvider(address(WEETH)).getRate(); // [weETH / eETH]
        price = price.mulDivDown(weEthToEEthConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(eethExtension));
        priceRouter.addAsset(EETH, settings, abi.encode(0), price);

        // // check getValue()
        // assertApproxEqRel(
        //     priceRouter.getValue(EETH, 1e18, WEETH), // should be [WEETH / EETH]
        //     weEthToEEthConversion,
        //     1e8,
        //     "WEETH value in EETH should approx equal conversion."
        // );
    }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithWrongAsset() external {
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        // Setup dependent price feeds.
        _addDependentPriceFeeds();

        // Add wstEth.
        PriceRouter.AssetSettings memory settings;

        // Add eETH.
        uint256 weEthToEEthConversion = IRateProvider(address(WEETH)).getRate(); // [weETH / eETH]
        price = price.mulDivDown(weEthToEEthConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(eethExtension));

        address notWSTETH = vm.addr(123);
        vm.expectRevert(bytes(abi.encodeWithSelector(eEthExtension.eEthExtension__ASSET_NOT_EETH.selector)));
        priceRouter.addAsset(ERC20(notWSTETH), settings, abi.encode(0), price);
    }

    function testAddingWstethWithoutPricingSteth() external {
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());

        // Add wstEth.
        PriceRouter.AssetSettings memory settings;
        // Add eETH.
        uint256 weEthToEEthConversion = IRateProvider(address(WEETH)).getRate(); // [weETH / eETH]
        price = price.mulDivDown(weEthToEEthConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(eethExtension));

        vm.expectRevert(bytes(abi.encodeWithSelector(eEthExtension.eEthExtension__WEETH_NOT_SUPPORTED.selector)));
        priceRouter.addAsset(EETH, settings, abi.encode(0), price);
    }

    function _addDependentPriceFeeds() internal {
        mockRedstoneClassicAdapter = new MockRedstoneClassicAdapter();
        redstonePriceFeedExtension = new RedstonePriceFeedExtension(priceRouter);
        eethExtension = new eEthExtension(priceRouter);

        // wstethExtension = new WstEthExtension(priceRouter);

        PriceRouter.AssetSettings memory settings;

        // TODO - shouldn't price router already have weth and usdc in it?

        // setup price for WEETH in price router using mock redstone oracle for weETH
        bytes32 weethDataFeedId = bytes32("WEETH");

        // TODO - setup actual redstone
        mockRedstoneClassicAdapter.setValueForDataFeed(weethDataFeedId, 1e8);
        mockRedstoneClassicAdapter.setTimestampsFromLatestUpdate(uint128(block.timestamp));

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));

        RedstonePriceFeedExtension.ExtensionStorage memory stor;
        stor.dataFeedId = weethDataFeedId;
        stor.heartbeat = 1 days;
        stor.redstoneAdapter = IRedstoneAdapter(address(mockRedstoneClassicAdapter));

        priceRouter.addAsset(WEETH, settings, abi.encode(stor), 1e8);
    }
}
