// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract WstEthExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    // Deploy the extension.
    WstEthExtension private wstethExtension;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        wstethExtension = new WstEthExtension(priceRouter);

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
    function testWstEthExtension() external {
        // Setup dependent price feeds.
        PriceRouter.AssetSettings memory settings;
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        // Add wstEth.
        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);

        assertApproxEqRel(
            priceRouter.getValue(WSTETH, 1e18, STETH),
            wstethToStethConversion,
            1e8,
            "WSTETH value in STETH should approx equal conversion."
        );
    }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithWrongAsset() external {
        // Add wstEth.
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());

        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));

        address notWSTETH = vm.addr(123);
        vm.expectRevert(bytes(abi.encodeWithSelector(WstEthExtension.WstEthExtension__ASSET_NOT_WSTETH.selector)));
        priceRouter.addAsset(ERC20(notWSTETH), settings, abi.encode(0), price);
    }

    function testAddingWstethWithoutPricingSteth() external {
        // Add wstEth.
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());

        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        vm.expectRevert(bytes(abi.encodeWithSelector(WstEthExtension.WstEthExtension__STETH_NOT_SUPPORTED.selector)));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);
    }
}
