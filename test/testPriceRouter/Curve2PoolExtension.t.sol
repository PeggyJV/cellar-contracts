// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Curve2PoolExtension, CurvePool, Extension } from "src/modules/price-router/Extensions/Curve/Curve2PoolExtension.sol";
import { CurveEMAExtension, CurvePool } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";
import { ERC4626Extension } from "src/modules/price-router/Extensions/ERC4626Extension.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { MockCurvePricingSource } from "src/mocks/MockCurvePricingSource.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract Curve2PoolExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    // Deploy the extension.
    Curve2PoolExtension private curve2PoolExtension;
    CurveEMAExtension private curveEMAExtension;
    ERC4626Extension private erc4626Extension;
    MockCurvePricingSource private mockCurvePricingSource;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18592956;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        curve2PoolExtension = new Curve2PoolExtension(priceRouter, address(WETH), 18);
        curveEMAExtension = new CurveEMAExtension(priceRouter, address(WETH), 18);
        erc4626Extension = new ERC4626Extension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        // priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), 1e8);

        // Add CrvUsd
        CurveEMAExtension.ExtensionStorage memory cStor;
        cStor.pool = UsdcCrvUsdPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.upperBound = uint32(1.05e4); //TODO:
        cStor.lowerBound = uint32(.95e4); //TODO:

        uint256 price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(USDC), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(CRVUSD, settings, abi.encode(cStor), price); // TODO: I believe this is where the setup is failing currently.

        ERC4626 sDaiVault = ERC4626(savingsDaiAddress);
        ERC20 sDAI = ERC20(savingsDaiAddress);
        uint256 oneSDaiShare = 10 ** sDaiVault.decimals();
        uint256 sDaiShareInDai = sDaiVault.previewRedeem(oneSDaiShare);
        price = priceRouter.getPriceInUSD(DAI).mulDivDown(sDaiShareInDai, 10 ** DAI.decimals());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(erc4626Extension));
        priceRouter.addAsset(sDAI, settings, abi.encode(0), price);

        // TODO: add a mockCurvePricingSource (setup extension, add asset to priceRouter, trust Curve position with asset, trust ConvexCurve position with asset, test reverts)
    }

    // ======================================= HAPPY PATH =======================================
    function testUsingExtensionWithUncorrelatedAssets() external {
        _addWethToPriceRouter();
        _addRethToPriceRouter();

        Curve2PoolExtension.ExtensionStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curve2PoolExtension));

        stor.pool = WethRethPool;
        stor.underlyingOrConstituent0 = address(WETH);
        stor.underlyingOrConstituent1 = address(rETH);

        stor.lowerBound = .95e4;
        stor.upperBound = 1.05e4;

        priceRouter.addAsset(ERC20(WethRethToken), settings, abi.encode(stor), 4_076e8);

        uint256 price = priceRouter.getValue(ERC20(WethRethToken), 1e18, WETH);

        assertApproxEqRel(price, 2.1257e18, 0.0001e18, "LP price in ETH should be ~2.1257.");
    }

    function testUsingExtensionWithCorrelatedAssets() external {
        Curve2PoolExtension.ExtensionStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curve2PoolExtension));

        stor.pool = FraxCrvUsdPool;
        stor.underlyingOrConstituent0 = address(FRAX);
        stor.underlyingOrConstituent1 = address(CRVUSD);
        stor.isCorrelated = true;
        stor.lowerBound = .95e4;
        stor.upperBound = 1.05e4;

        priceRouter.addAsset(ERC20(FraxCrvUsdToken), settings, abi.encode(stor), 1e8);

        uint256 price = priceRouter.getValue(ERC20(FraxCrvUsdToken), 1e18, USDC);

        assertApproxEqRel(price, 1e6, 0.0002e18, "LP price in USDC should be ~1.");
    }

    function testUsingExtensionWithCorrelatedAssetsWithRates() external {
        Curve2PoolExtension.ExtensionStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curve2PoolExtension));

        stor.pool = CrvUsdSdaiPool;
        stor.underlyingOrConstituent0 = address(CRVUSD);
        stor.underlyingOrConstituent1 = address(sDAI);
        stor.isCorrelated = true;
        stor.divideRate1 = true;
        stor.lowerBound = .95e4;
        stor.upperBound = 1.05e4;

        priceRouter.addAsset(ERC20(CrvUsdSdaiToken), settings, abi.encode(stor), 1e8);

        uint256 price = priceRouter.getValue(ERC20(CrvUsdSdaiToken), 1e18, USDC);

        assertApproxEqRel(price, 1e6, 0.001e18, "LP price in USDC should be ~1.");
    }

    // ======================================= REVERTS =======================================
    function testUnderlyingOrConstituent0NotSupported() external {
        Curve2PoolExtension.ExtensionStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curve2PoolExtension));

        stor.pool = WethRethPool;
        stor.underlyingOrConstituent0 = address(WETH);
        stor.underlyingOrConstituent1 = address(rETH);
        stor.lowerBound = .95e4;
        stor.upperBound = 1.05e4;

        vm.expectRevert(
            bytes(abi.encodeWithSelector(Curve2PoolExtension.Curve2PoolExtension_ASSET_NOT_SUPPORTED.selector))
        );
        priceRouter.addAsset(ERC20(WethRethToken), settings, abi.encode(stor), 4_076e8);

        // Add unsupported asset.
        _addWethToPriceRouter();

        // Pricing call still fails because coins1 is not supported.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Curve2PoolExtension.Curve2PoolExtension_ASSET_NOT_SUPPORTED.selector))
        );
        priceRouter.addAsset(ERC20(WethRethToken), settings, abi.encode(stor), 4_076e8);

        // Add unsupported asset.
        _addRethToPriceRouter();

        // Pricing call is now successful.
        priceRouter.addAsset(ERC20(WethRethToken), settings, abi.encode(stor), 4_076e8);
    }

    function testUnderlyingOrConstituent1NotSupported() external {
        _addWethToPriceRouter();

        Curve2PoolExtension.ExtensionStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curve2PoolExtension));

        stor.pool = WethFrxethPool;
        stor.underlyingOrConstituent0 = address(WETH);
        stor.underlyingOrConstituent1 = address(FRXETH);
        stor.isCorrelated = true;
        stor.lowerBound = .95e4;
        stor.upperBound = 1.05e4;

        vm.expectRevert(
            bytes(abi.encodeWithSelector(Curve2PoolExtension.Curve2PoolExtension_ASSET_NOT_SUPPORTED.selector))
        );
        priceRouter.addAsset(ERC20(WethFrxethToken), settings, abi.encode(stor), 0);

        // Add unsupported asset.
        CurveEMAExtension.ExtensionStorage memory cStor;
        PriceRouter.AssetSettings memory cSettings;
        cStor.pool = WethFrxethPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.lowerBound = .95e4;
        cStor.upperBound = 1.05e4;

        uint256 price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        cSettings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(FRXETH, cSettings, abi.encode(cStor), price);

        // Pricing call is successful.
        priceRouter.addAsset(ERC20(WethFrxethToken), settings, abi.encode(stor), price);
    }

    function testMismatchingCorrelatedAndUncorrelatedPool() external {
        Curve2PoolExtension.ExtensionStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curve2PoolExtension));

        stor.pool = FraxCrvUsdPool;
        stor.underlyingOrConstituent0 = address(FRAX);
        stor.underlyingOrConstituent1 = address(CRVUSD);
        // isCorrelated should be true.
        stor.isCorrelated = false;
        stor.lowerBound = .95e4;
        stor.upperBound = 1.05e4;

        vm.expectRevert(
            bytes(abi.encodeWithSelector(Curve2PoolExtension.Curve2PoolExtension_POOL_NOT_SUPPORTED.selector))
        );
        priceRouter.addAsset(ERC20(FraxCrvUsdToken), settings, abi.encode(stor), 1e8);

        stor.isCorrelated = true;

        // Call now works.
        priceRouter.addAsset(ERC20(FraxCrvUsdToken), settings, abi.encode(stor), 1e8);
    }

    function testUsingExtensionWith3Pool() external {
        Curve2PoolExtension.ExtensionStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curve2PoolExtension));

        stor.pool = TriCryptoPool;

        vm.expectRevert(
            bytes(abi.encodeWithSelector(Curve2PoolExtension.Curve2PoolExtension_POOL_NOT_SUPPORTED.selector))
        );
        priceRouter.addAsset(ERC20(CRV_3_CRYPTO), settings, abi.encode(stor), 0);
    }

    function testCallingSetupFromWrongAddress() external {
        vm.expectRevert(bytes(abi.encodeWithSelector(Extension.Extension__OnlyPriceRouter.selector)));
        curve2PoolExtension.setupSource(USDC, abi.encode(0));
    }

    /**
     * TODO: test the new pricing bounds applied to curve pricing extensions (applies to curve 2pool, and curve ema pricing extensions)
     * NOTE: uses mockCurvePricingSource.sol to assess how the extensions respond to different scenarios from curve pool.
     */
    function testEnforceBounds() external {
        // setup should have a mockCurvePool setup to work with one asset already registered with priceRouter, registry, curveAdaptor, and convexCurveAdaptor
        // test reversion
        // test resolution of reversion
    }

    function _addWethToPriceRouter() internal {
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);
    }

    function _addRethToPriceRouter() internal {
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;
        stor.inETH = true;

        uint256 price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);
    }
}
