// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {eEthExtension} from "src/modules/price-router/Extensions/EtherFi/eEthExtension.sol";
import {AdaptorHelperFunctions} from "test/resources/AdaptorHelperFunctions.sol";
import {RedstonePriceFeedExtension} from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import {IRedstoneAdapter} from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import {IRateProvider} from "src/interfaces/external/EtherFi/IRateProvider.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

contract eEthExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    RedstonePriceFeedExtension private redstonePriceFeedExtension;

    // Deploy the extension.
    eEthExtension private eethExtension;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19277858;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        eethExtension = new eEthExtension(priceRouter);
    }

    // ======================================= HAPPY PATH =======================================
    function testAddEEthExtension() external {
        // Setup dependent price feeds.
        _addDependentPriceFeeds();

        PriceRouter.AssetSettings memory settings;
        uint256 price = priceRouter.getPriceInUSD(WEETH); // 8 decimals

        // Add eETH.
        uint256 weEthToEEthConversion = IRateProvider(address(WEETH)).getRate(); // [weETH / eETH]

        price = price.mulDivDown(10 ** weETH.decimals(), IRateProvider(address(WEETH)).getRate());

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(eethExtension));
        priceRouter.addAsset(EETH, settings, abi.encode(0), price);

        // check getValue()
        assertApproxEqRel(
            priceRouter.getValue(WEETH, 1e18, EETH),
            weEthToEEthConversion,
            1e8,
            "WEETH value in EETH should approx equal conversion."
        );
    }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithWrongAsset() external {
        // Setup dependent price feeds.
        _addDependentPriceFeeds();

        PriceRouter.AssetSettings memory settings;
        uint256 price = priceRouter.getPriceInUSD(WEETH); // 8 decimals

        // Add eETH.
        uint256 weEthToEEthConversion = IRateProvider(address(WEETH)).getRate(); // [weETH / eETH]
        price = weEthToEEthConversion.mulDivDown(price, 10 ** WEETH.decimals());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(eethExtension));

        address notWSTETH = vm.addr(123);
        vm.expectRevert(bytes(abi.encodeWithSelector(eEthExtension.eEthExtension__ASSET_NOT_EETH.selector)));
        priceRouter.addAsset(ERC20(notWSTETH), settings, abi.encode(0), price);
    }

    function testAddingEethWithoutPricingWeEth() external {
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        PriceRouter.AssetSettings memory settings;

        // Add eETH.
        uint256 weEthToEEthConversion = IRateProvider(address(WEETH)).getRate(); // [weETH / eETH]
        price = weEthToEEthConversion.mulDivDown(price, 10 ** WEETH.decimals());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(eethExtension));

        vm.expectRevert(bytes(abi.encodeWithSelector(eEthExtension.eEthExtension__WEETH_NOT_SUPPORTED.selector)));
        priceRouter.addAsset(EETH, settings, abi.encode(0), price);
    }

    // NOTE: this is for weETH:USD datafeed
    function _addDependentPriceFeeds() internal {
        redstonePriceFeedExtension = new RedstonePriceFeedExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));
        RedstonePriceFeedExtension.ExtensionStorage memory rstor;
        rstor.dataFeedId = weethUsdDataFeedId;
        rstor.heartbeat = 1 days;
        rstor.redstoneAdapter = IRedstoneAdapter(weethAdapter);
        price = IRedstoneAdapter(weethAdapter).getValueForDataFeed(rstor.dataFeedId);
        priceRouter.addAsset(WEETH, settings, abi.encode(rstor), price);
    }
}
