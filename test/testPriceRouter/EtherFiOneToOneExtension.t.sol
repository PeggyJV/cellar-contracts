// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {weEthExtension} from "src/modules/price-router/Extensions/EtherFi/weEthExtension.sol";
import {AdaptorHelperFunctions} from "test/resources/AdaptorHelperFunctions.sol";
import {RedstonePriceFeedExtension} from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import {IRedstoneAdapter} from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import {IRateProvider} from "src/interfaces/external/EtherFi/IRateProvider.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

contract weEthExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    // Deploy the extension.
    weEthExtension private weethExtension;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19277858;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        weethExtension = new weEthExtension(priceRouter);
    }

    // ======================================= HAPPY PATH =======================================
    function testAddWtEEthExtension() external {
        // Setup dependent price feeds.
        _addDependentPriceFeeds();

        PriceRouter.AssetSettings memory settings;
        uint256 price = priceRouter.getPriceInUSD(WETH); // 8 decimals

        // Add weETH.
        uint256 weEthToEEthConversion = IRateProvider(address(WEETH)).getRate(); // [weETH / eETH]

        price = price.mulDivDown(IRateProvider(address(WEETH)).getRate(), 10 ** weETH.decimals());

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(weethExtension));
        priceRouter.addAsset(WEETH, settings, abi.encode(0), price);

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
        settings.derivative = EXTENSION_DERIVATIVE;
        settings.source = address(weethExtension);

        address notWSTETH = vm.addr(123);
        vm.expectRevert(bytes(abi.encodeWithSelector(weEthExtension.weEthExtension__ASSET_NOT_WEETH.selector)));
        priceRouter.addAsset(ERC20(notWSTETH), settings, abi.encode(0), 0);
    }

    function testAddingWeethWithoutPricingWeth() external {
        PriceRouter.AssetSettings memory settings;
        settings.derivative = EXTENSION_DERIVATIVE;
        settings.source = address(weethExtension);

        vm.expectRevert(bytes(abi.encodeWithSelector(weEthExtension.weEthExtension__WETH_NOT_SUPPORTED.selector)));
        priceRouter.addAsset(WEETH, settings, abi.encode(0), 0);
    }

    // NOTE: this is for wETH:USD, and eETH:USD datafeeds
    function _addDependentPriceFeeds() internal {
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(EETH, settings, abi.encode(stor), price);
    }
}
