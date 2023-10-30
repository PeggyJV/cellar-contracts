// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CurveEMAExtension, CurvePool } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CurveEMAExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    // Deploy the extension.
    CurveEMAExtension private curveEMAExtension;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        curveEMAExtension = new CurveEMAExtension(priceRouter, address(WETH), 18);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);
    }

    // ======================================= HAPPY PATH =======================================
    function testCurveEMAExtensionFrxEth() external {
        _addWethToPriceRouter();
        // Add FrxEth to price router.
        CurveEMAExtension.ExtensionStorage memory stor;
        stor.pool = EthFrxEthCurvePool;
        stor.index = 0;
        stor.needIndex = false;
        PriceRouter.AssetSettings memory settings;
        uint256 price = curveEMAExtension.getPriceFromCurvePool(CurvePool(stor.pool), stor.index, stor.needIndex);
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(FRXETH, settings, abi.encode(stor), price);

        uint256 frxEthPrice = priceRouter.getValue(FRXETH, 1e18, WETH);

        assertApproxEqRel(frxEthPrice, 1e18, 0.001e18, "FrxEth price should approximately equal 1 ETH.");
    }

    // Note tri crypto curve pool EMA gives price with 18 decimals eventhough coins[0] is USDT(with 6 decimals).
    function testCurveEMAExtensionTriCrypto2() external {
        _addWethToPriceRouter();

        // Add WBTC to price router.
        CurveEMAExtension.ExtensionStorage memory stor;
        stor.pool = triCrypto2;
        stor.index = 0;
        stor.needIndex = true;
        PriceRouter.AssetSettings memory settings;
        uint256 price = curveEMAExtension.getPriceFromCurvePool(CurvePool(stor.pool), stor.index, stor.needIndex);
        price = price.changeDecimals(18, 8);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        uint256 wbtcPrice = priceRouter.getValue(WBTC, 1e8, WETH);

        assertApproxEqRel(wbtcPrice, 15.81e18, 0.001e18, "WBTC price should approximately equal 15.81 ETH.");
    }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithUnsupportedAsset() external {
        CurveEMAExtension.ExtensionStorage memory stor;
        stor.pool = EthFrxEthCurvePool;
        stor.index = 0;
        stor.needIndex = false;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CurveEMAExtension.CurveEMAExtension_ASSET_NOT_SUPPORTED.selector))
        );
        priceRouter.addAsset(FRXETH, settings, abi.encode(stor), 0);

        // Add WETH to price router.
        _addWethToPriceRouter();

        uint256 price = curveEMAExtension.getPriceFromCurvePool(CurvePool(stor.pool), stor.index, stor.needIndex);
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);

        // Now sDAI can be added.
        priceRouter.addAsset(FRXETH, settings, abi.encode(stor), price);
    }

    function _addWethToPriceRouter() internal {
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);
    }
}
