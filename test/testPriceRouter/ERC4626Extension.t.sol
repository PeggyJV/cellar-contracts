// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626Extension } from "src/modules/price-router/Extensions/ERC4626Extension.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract ERC4626ExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    // Deploy the extension.
    ERC4626Extension private erc4626Extension;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        erc4626Extension = new ERC4626Extension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);
    }

    // ======================================= HAPPY PATH =======================================
    function testERC4626ExtensionSDai() external {
        _addDaiToPriceRouter();
        // Add sDAI to price router.
        PriceRouter.AssetSettings memory settings;
        ERC4626 sDaiVault = ERC4626(savingsDaiAddress);
        ERC20 sDAI = ERC20(savingsDaiAddress);
        uint256 oneSDaiShare = 10 ** sDaiVault.decimals();
        uint256 sDaiShareInDai = sDaiVault.previewRedeem(oneSDaiShare);
        uint256 price = priceRouter.getPriceInUSD(DAI).mulDivDown(sDaiShareInDai, 10 ** DAI.decimals());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(erc4626Extension));
        priceRouter.addAsset(sDAI, settings, abi.encode(0), price);

        uint256 sDaiPrice = priceRouter.getPriceInUSD(sDAI);

        uint256 expectedSDaiPrice = sDaiShareInDai.mulDivDown(priceRouter.getPriceInUSD(DAI), 10 ** DAI.decimals());

        assertApproxEqRel(expectedSDaiPrice, sDaiPrice, 0.00001e18, "Expected sDAI price does not equal actual.");

        // sDAI price in DAI should equal the preview redeem amount for one share.
        uint256 sDaiPriceInDai = priceRouter.getValue(sDAI, oneSDaiShare, DAI);
        assertApproxEqRel(
            sDaiShareInDai,
            sDaiPriceInDai,
            0.00001e18,
            "sDAI value in terms of DAI should equal preview redeem amount."
        );
    }

    function testERC4626ExtensionRYUSD() external {
        _addDaiToPriceRouter();
        // Add sDAI to price router.
        PriceRouter.AssetSettings memory settings;
        ERC4626 ryusdCellar = ERC4626(ryusdAddress);
        ERC20 ryusd = ERC20(ryusdAddress);
        uint256 oneRYUSDShare = 10 ** ryusdCellar.decimals();
        uint256 ryusdShareInUsdc = ryusdCellar.previewRedeem(oneRYUSDShare);
        uint256 price = priceRouter.getPriceInUSD(USDC).mulDivDown(ryusdShareInUsdc, 10 ** USDC.decimals());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(erc4626Extension));
        priceRouter.addAsset(ryusd, settings, abi.encode(0), price);

        uint256 ryusdPrice = priceRouter.getPriceInUSD(ryusd);

        uint256 expectedRYUSDPrice = ryusdShareInUsdc.mulDivDown(
            priceRouter.getPriceInUSD(USDC),
            10 ** USDC.decimals()
        );

        assertApproxEqRel(expectedRYUSDPrice, ryusdPrice, 0.00001e18, "Expected RYUSD price does not equal actual.");

        // RYUSD price in USDC should equal the preview redeem amount for one share.
        uint256 ryusdPriceInUsdc = priceRouter.getValue(ryusd, oneRYUSDShare, USDC);
        assertApproxEqRel(
            ryusdShareInUsdc,
            ryusdPriceInUsdc,
            0.00001e18,
            "RYUSD value in terms of USDC should equal preview redeem amount."
        );
    }

    // TODO once we have a data source for frxEth, try using this extension to price frxEth.

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithUnsupportedAsset() external {
        PriceRouter.AssetSettings memory settings;
        ERC4626 sDaiVault = ERC4626(savingsDaiAddress);
        ERC20 sDAI = ERC20(savingsDaiAddress);
        uint256 oneSDaiShare = 10 ** sDaiVault.decimals();
        uint256 sDaiShareInDai = sDaiVault.previewRedeem(oneSDaiShare);
        uint256 price = 1e8;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(erc4626Extension));

        vm.expectRevert(bytes(abi.encodeWithSelector(ERC4626Extension.ERC4626Extension_ASSET_NOT_SUPPORTED.selector)));
        priceRouter.addAsset(sDAI, settings, abi.encode(0), price);

        // Add DAI to price router.
        _addDaiToPriceRouter();
        price = priceRouter.getPriceInUSD(DAI).mulDivDown(sDaiShareInDai, 10 ** DAI.decimals());

        // Now sDAI can be added.
        priceRouter.addAsset(sDAI, settings, abi.encode(0), price);
    }

    function _addDaiToPriceRouter() internal {
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);
    }
}
