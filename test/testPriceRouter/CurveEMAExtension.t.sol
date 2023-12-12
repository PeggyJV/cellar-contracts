// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CurveEMAExtension, CurvePool } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MockCurvePricingSource } from "src/mocks/MockCurvePricingSource.sol";

contract CurveEMAExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    // Deploy the extension.
    CurveEMAExtension private curveEMAExtension;

    MockCurvePricingSource private mockCurvePricingSource;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18514604;
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

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        // Add CrvUsd
        CurveEMAExtension.ExtensionStorage memory cStor;
        cStor.pool = UsdcCrvUsdPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.lowerBound = 0;
        cStor.upperBound = 10e4;
        uint256 price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(USDC), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(CRVUSD, settings, abi.encode(cStor), price);
    }

    // ======================================= HAPPY PATH =======================================
    function testCurveEMAExtensionFrxEth() external {
        _addWethToPriceRouter();
        // Add FrxEth to price router.
        CurveEMAExtension.ExtensionStorage memory stor;
        stor.pool = EthFrxEthCurvePool;
        stor.index = 0;
        stor.needIndex = false;
        stor.lowerBound = 0;
        stor.upperBound = 10e4;
        PriceRouter.AssetSettings memory settings;
        uint256 price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(stor.pool),
            stor.index,
            stor.needIndex,
            stor.rateIndex,
            stor.handleRate
        );
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
        stor.lowerBound = 0;
        stor.upperBound = 10e8;
        PriceRouter.AssetSettings memory settings;
        uint256 price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(stor.pool),
            stor.index,
            stor.needIndex,
            stor.rateIndex,
            stor.handleRate
        );
        price = price.changeDecimals(18, 8);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        uint256 wbtcPrice = priceRouter.getValue(WBTC, 1e8, WETH);

        assertApproxEqRel(wbtcPrice, 18.46e18, 0.001e18, "WBTC price should approximately equal 15.81 ETH.");
    }

    function testCurveEMAExtensionEthx() external {
        _addWethToPriceRouter();
        // Add FrxEth to price router.
        CurveEMAExtension.ExtensionStorage memory stor;
        stor.pool = EthEthxPool;
        stor.index = 0;
        stor.needIndex = false;
        stor.rateIndex = 1;
        stor.handleRate = true;
        stor.lowerBound = 0;
        stor.upperBound = 10e4;
        PriceRouter.AssetSettings memory settings;
        uint256 price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(stor.pool),
            stor.index,
            stor.needIndex,
            stor.rateIndex,
            stor.handleRate
        );
        CurvePool pool = CurvePool(EthEthxPool);
        uint256[2] memory rates = pool.stored_rates();
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        price = price.mulDivDown(rates[1], 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(ETHX, settings, abi.encode(stor), price);

        uint256 ethXPrice = priceRouter.getValue(ETHX, 1e18, WETH);

        assertApproxEqRel(ethXPrice, rates[1], 0.002e18, "ETHx price should approximately equal the ETHx rate.");
    }

    function testCurveEMAExtensionSDai() external {
        _addWethToPriceRouter();
        // Add FrxEth to price router.
        CurveEMAExtension.ExtensionStorage memory stor;
        stor.pool = CrvUsdSdaiPool;
        stor.index = 0;
        stor.needIndex = false;
        stor.rateIndex = 1;
        stor.handleRate = true;
        stor.lowerBound = 0;
        stor.upperBound = 10e4;
        PriceRouter.AssetSettings memory settings;
        uint256 price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(stor.pool),
            stor.index,
            stor.needIndex,
            stor.rateIndex,
            stor.handleRate
        );
        CurvePool pool = CurvePool(EthEthxPool);
        uint256[2] memory rates = pool.stored_rates();
        price = price.mulDivDown(priceRouter.getPriceInUSD(DAI), 1e18);
        price = price.mulDivDown(rates[1], 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(ERC20(sDAI), settings, abi.encode(stor), price);

        uint256 sDaiPrice = priceRouter.getValue(ERC20(sDAI), 1e18, DAI);
        uint256 expectedPrice = ERC4626(sDAI).previewRedeem(1e18);
        assertApproxEqRel(sDaiPrice, expectedPrice, 0.002e18, "sDAI price should approximately equal the sDAI rate.");
    }

    /**
     * test the new pricing bounds (_enforceBounds()) applied to a asset being setup - upperBound focus
     */
    function testEnforceBoundsSetupUpperBound() external {
        _addWethToPriceRouter();

        // Add FrxEth mock pricing source
        CurveEMAExtension.ExtensionStorage memory cStor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));

        uint256 price;

        address[2] memory _coins = [
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0x5E8422345238F34275888049021821E8E08CAa1f
        ];
        uint256[2] memory _rates;

        mockCurvePricingSource = new MockCurvePricingSource(_coins, _rates, 1e18, 1e18);

        cStor.pool = address(mockCurvePricingSource); // was WethFrxethPool originally
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.lowerBound = 0;
        cStor.upperBound = .8e4; // purposely set upperBound low
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));

        vm.expectRevert(bytes(abi.encodeWithSelector(CurveEMAExtension.CurveEMAExtension_BOUNDS_EXCEEDED.selector)));
        priceRouter.addAsset(FRXETH, settings, abi.encode(cStor), price);

        cStor.lowerBound = 0;
        cStor.upperBound = 1e4; // resolve upperBound
        priceRouter.addAsset(FRXETH, settings, abi.encode(cStor), price);
    }

    /**
     * test the new pricing bounds (_enforceBounds()) applied to a asset being setup - lowerBound focus
     */
    function testEnforceBoundsSetupLowerBound() external {
        _addWethToPriceRouter();

        // Add FrxEth mock pricing source
        CurveEMAExtension.ExtensionStorage memory cStor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));

        uint256 price;

        address[2] memory _coins = [
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0x5E8422345238F34275888049021821E8E08CAa1f
        ];
        uint256[2] memory _rates;

        mockCurvePricingSource = new MockCurvePricingSource(_coins, _rates, 1e18, 1e18);

        cStor.pool = address(mockCurvePricingSource); // was WethFrxethPool originally
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.lowerBound = 2e4; // purposely set lowerBound high
        cStor.upperBound = 1.05e4;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));

        vm.expectRevert(bytes(abi.encodeWithSelector(CurveEMAExtension.CurveEMAExtension_BOUNDS_EXCEEDED.selector)));
        priceRouter.addAsset(FRXETH, settings, abi.encode(cStor), price);

        cStor.lowerBound = .95e4; // resolve lowerBound
        cStor.upperBound = 1.05e4;
        priceRouter.addAsset(FRXETH, settings, abi.encode(cStor), price);
    }

    // add mock
    // add asset
    // trigger upper revert with getPriceInUSD
    // resolve
    // trigger lower revert with getPriceInUSD
    // resolve
    function testEnforceBounds() external {
        _addWethToPriceRouter();

        // Add FrxEth mock pricing source
        CurveEMAExtension.ExtensionStorage memory cStor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));

        uint256 price;

        address[2] memory _coins = [
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0x5E8422345238F34275888049021821E8E08CAa1f
        ];
        uint256[2] memory _rates;

        mockCurvePricingSource = new MockCurvePricingSource(_coins, _rates, 1e18, 1e18);

        cStor.pool = address(mockCurvePricingSource); // was WethFrxethPool originally
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.lowerBound = .95e4;
        cStor.upperBound = 1e4;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(FRXETH, settings, abi.encode(cStor), price);

        // ensure getPriceInUSD does not revert
        priceRouter.getPriceInUSD(FRXETH);

        mockCurvePricingSource.setMockPriceOraclePrice(.5e18); //should trigger lowerbound
        vm.expectRevert(bytes(abi.encodeWithSelector(CurveEMAExtension.CurveEMAExtension_BOUNDS_EXCEEDED.selector)));
        priceRouter.getPriceInUSD(FRXETH);

        mockCurvePricingSource.setMockPriceOraclePrice(1e18); // resolve and show that getPriceInUSD works now
        priceRouter.getPriceInUSD(FRXETH);

        mockCurvePricingSource.setMockPriceOraclePrice(10e18); //should trigger upperbound
        vm.expectRevert(bytes(abi.encodeWithSelector(CurveEMAExtension.CurveEMAExtension_BOUNDS_EXCEEDED.selector)));
        priceRouter.getPriceInUSD(FRXETH);

        mockCurvePricingSource.setMockPriceOraclePrice(1e18); // resolve and show that getPriceInUSD works now
        priceRouter.getPriceInUSD(FRXETH);
    }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithUnsupportedAsset() external {
        CurveEMAExtension.ExtensionStorage memory stor;
        stor.pool = EthFrxEthCurvePool;
        stor.index = 0;
        stor.needIndex = false;
        stor.lowerBound = 0;
        stor.upperBound = 10e4;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CurveEMAExtension.CurveEMAExtension_ASSET_NOT_SUPPORTED.selector))
        );
        priceRouter.addAsset(FRXETH, settings, abi.encode(stor), 0);

        // Add WETH to price router.
        _addWethToPriceRouter();

        uint256 price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(stor.pool),
            stor.index,
            stor.needIndex,
            stor.rateIndex,
            stor.handleRate
        );
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
