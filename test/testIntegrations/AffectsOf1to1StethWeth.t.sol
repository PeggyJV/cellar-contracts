// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { LegacyCellarAdaptor } from "src/modules/adaptors/Sommelier/LegacyCellarAdaptor.sol";
import { LegacyRegistry } from "src/interfaces/LegacyRegistry.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

interface RYECachePriceRouter {
    function cachePriceRouter(bool checkTotalAssets, uint16 allowableRange) external;
}

contract AffectsOf1to1StethWethTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar public rye = Cellar(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);
    Cellar public turboSteth = Cellar(0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971);

    PriceRouter public isolatedPriceRouter;
    WstEthExtension private wstethExtension;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18443373;
        _startFork(rpcKey, blockNumber);

        isolatedPriceRouter = new PriceRouter(address(this), turboSteth.registry(), WETH);
        wstethExtension = new WstEthExtension(isolatedPriceRouter);

        priceRouter = PriceRouter(address(rye.priceRouter()));

        // Add assets to isolated price router.
        _addChainlinkAsset(isolatedPriceRouter, WETH, WETH_USD_FEED, false);
        // Make STETH 1:1 with WETH by making it use the WETH USD Chainlink Feed.
        _addChainlinkAsset(isolatedPriceRouter, STETH, WETH_USD_FEED, false);
        _addChainlinkAsset(isolatedPriceRouter, rETH, RETH_ETH_FEED, true);
        _addChainlinkAsset(isolatedPriceRouter, cbETH, CBETH_ETH_FEED, true);

        PriceRouter.AssetSettings memory settings;
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());

        // Add wstEth.
        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        isolatedPriceRouter.addAsset(WSTETH, settings, abi.encode(0), price);
    }

    function testImmediateAffectsOfChange() external {
        // make the change, and see how much share price changes.
        uint256 ryeTotalAssetsBefore = rye.totalAssets();
        uint256 turboStethTotalAssetsBefore = turboSteth.totalAssets();

        // Update both registries price routers to point to isolated one.
        vm.startPrank(multisig);
        Registry(rye.registry()).setAddress(2, address(isolatedPriceRouter));
        Registry(turboSteth.registry()).setAddress(2, address(isolatedPriceRouter));
        vm.stopPrank();

        // Have both cellars cache the new price router.
        vm.startPrank(gravityBridgeAddress);
        RYECachePriceRouter(address(rye)).cachePriceRouter(true, 16);
        turboSteth.cachePriceRouter(true, 16, address(isolatedPriceRouter));
        vm.stopPrank();

        // Update both registries price routers to point to old one.
        vm.startPrank(multisig);
        Registry(rye.registry()).setAddress(2, address(priceRouter));
        Registry(turboSteth.registry()).setAddress(2, address(priceRouter));
        vm.stopPrank();

        uint256 ryeTotalAssetsAfter = rye.totalAssets();
        uint256 turboStethTotalAssetsAfter = turboSteth.totalAssets();

        assertGt(ryeTotalAssetsAfter, ryeTotalAssetsBefore, "Total assets should have increased.");
        assertGt(turboStethTotalAssetsAfter, turboStethTotalAssetsBefore, "Total assets should have increased.");

        assertApproxEqRel(
            ryeTotalAssetsAfter,
            ryeTotalAssetsBefore,
            0.002e18,
            "Total Assets should have changed, but not drastically."
        );
        assertApproxEqRel(
            turboStethTotalAssetsAfter,
            turboStethTotalAssetsBefore,
            0.002e18,
            "Total Assets should have changed, but not drastically."
        );
    }

    function testBlackSwanAffectsOfChange() external {
        // Update both registries price routers to point to isolated one.
        vm.startPrank(multisig);
        Registry(rye.registry()).setAddress(2, address(isolatedPriceRouter));
        Registry(turboSteth.registry()).setAddress(2, address(isolatedPriceRouter));
        vm.stopPrank();

        // Have both cellars cache the new price router.
        vm.startPrank(gravityBridgeAddress);
        RYECachePriceRouter(address(rye)).cachePriceRouter(true, 16);
        turboSteth.cachePriceRouter(true, 16, address(isolatedPriceRouter));
        vm.stopPrank();

        // Update both registries price routers to point to old one.
        vm.startPrank(multisig);
        Registry(rye.registry()).setAddress(2, address(priceRouter));
        Registry(turboSteth.registry()).setAddress(2, address(priceRouter));
        vm.stopPrank();

        // Now that Cellars have been updated to use new isolated price router, look at black swan affects.
        // Have steth depeg.
        // Uni positions woudl not be fully composed of steth, but cellar would evaluate them as fully composed of weth.
        // Aave would need to do some emergency gov prop to freeze new borrows, and possibly raise interest rate curve to start liquidating people, also also maybe something to change the oracle in aave to use chainlink?
        // IMO this is the biggest risk, a depeg happening, then Aave changing the oracle to use market price. There would be a lot of liquidations, and
        // The only way to sell would be to market sell at a huge loss, unstaking would take too long
        // But this risk is already present in RYE
    }

    function _addChainlinkAsset(PriceRouter router, ERC20 asset, address priceFeed, bool inEth) internal {
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        stor.inETH = inEth;

        uint256 price = uint256(IChainlinkAggregator(priceFeed).latestAnswer());
        if (inEth) {
            price = priceRouter.getValue(WETH, price, USDC);
            price = price.changeDecimals(6, 8);
        }

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, priceFeed);
        router.addAsset(asset, settings, abi.encode(stor), price);
    }
}
