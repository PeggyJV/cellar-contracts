// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { StEthExtension } from "src/modules/price-router/Extensions/Lido/StEthExtension.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract StEthExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    MockDataFeed private stethMockFeed;

    StEthExtension private stethExtension;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17780274;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        stethMockFeed = new MockDataFeed(STETH_ETH_FEED);

        stethExtension = new StEthExtension(
            priceRouter,
            50,
            stETHWethNg,
            address(stethMockFeed),
            1 days,
            address(WETH),
            address(STETH)
        );

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);
    }

    // ======================================= HAPPY PATH =======================================
    function testStEthExtension() external {
        // Setup dependent price feeds.
        PriceRouter.AssetSettings memory settings;

        // Add stEth.
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(stethExtension));
        priceRouter.addAsset(STETH, settings, abi.encode(0), price);

        assertApproxEqRel(
            priceRouter.getValue(STETH, 1e18, WETH),
            1e18,
            0.001e18,
            "STETH value in WETH should approx equal 1:1."
        );
    }

    // TODO test where we try to manipulate curve price.
    // TODO test where we make the values diverge, and make sure it is right.

    // // ======================================= REVERTS =======================================
    // function testUsingExtensionWithWrongAsset() external {
    //     // Add wstEth.
    //     PriceRouter.AssetSettings memory settings;
    //     uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());

    //     uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
    //     price = price.mulDivDown(wstethToStethConversion, 1e18);
    //     settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));

    //     address notWSTETH = vm.addr(123);
    //     vm.expectRevert(bytes(abi.encodeWithSelector(WstEthExtension.WstEthExtension__ASSET_NOT_WSTETH.selector)));
    //     priceRouter.addAsset(ERC20(notWSTETH), settings, abi.encode(0), price);
    // }

    // function testAddingWstethWithoutPricingSteth() external {
    //     // Add wstEth.
    //     PriceRouter.AssetSettings memory settings;
    //     uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());

    //     uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
    //     price = price.mulDivDown(wstethToStethConversion, 1e18);
    //     settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
    //     vm.expectRevert(bytes(abi.encodeWithSelector(WstEthExtension.WstEthExtension__STETH_NOT_SUPPORTED.selector)));
    //     priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);
    // }
}
