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

        curveEMAExtension = new CurveEMAExtension(priceRouter, address(WETH));

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

    // function testERC4626ExtensionRYUSD() external {
    //     _addDaiToPriceRouter();
    //     // Add sDAI to price router.
    //     PriceRouter.AssetSettings memory settings;
    //     ERC4626 ryusdCellar = ERC4626(ryusdAddress);
    //     ERC20 ryusd = ERC20(ryusdAddress);
    //     uint256 oneRYUSDShare = 10 ** ryusdCellar.decimals();
    //     uint256 ryusdShareInUsdc = ryusdCellar.previewRedeem(oneRYUSDShare);
    //     uint256 price = priceRouter.getPriceInUSD(USDC).mulDivDown(ryusdShareInUsdc, 10 ** USDC.decimals());
    //     settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(erc4626Extension));
    //     priceRouter.addAsset(ryusd, settings, abi.encode(0), price);

    //     uint256 ryusdPrice = priceRouter.getPriceInUSD(ryusd);

    //     uint256 expectedRYUSDPrice = ryusdShareInUsdc.mulDivDown(
    //         priceRouter.getPriceInUSD(USDC),
    //         10 ** USDC.decimals()
    //     );

    //     assertApproxEqRel(expectedRYUSDPrice, ryusdPrice, 0.00001e18, "Expected RYUSD price does not equal actual.");

    //     // RYUSD price in USDC should equal the preview redeem amount for one share.
    //     uint256 ryusdPriceInUsdc = priceRouter.getValue(ryusd, oneRYUSDShare, USDC);
    //     assertApproxEqRel(
    //         ryusdShareInUsdc,
    //         ryusdPriceInUsdc,
    //         0.00001e18,
    //         "RYUSD value in terms of USDC should equal preview redeem amount."
    //     );
    // }

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
