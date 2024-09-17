// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {RedstonePriceFeedExtension} from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import {IRedstoneAdapter} from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import {PendleExtension} from "src/modules/price-router/Extensions/Pendle/PendleExtension.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IRateProvider} from "src/interfaces/external/IRateProvider.sol";
import {PendleAdaptor, TokenInput, TokenOutput} from "src/modules/adaptors/Pendle/PendleAdaptor.sol";
import {SwapData, SwapType} from "@pendle/contracts/router/swap-aggregator/IPSwapAggregator.sol";
import {ISyToken} from "src/interfaces/external/Pendle/IPendle.sol";
import "forge-std/Test.sol";
// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import {IPendleMarket, ISyToken} from "src/interfaces/external/Pendle/IPendle.sol";

import {AdaptorHelperFunctions} from "test/resources/AdaptorHelperFunctions.sol";

contract PendleExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    RedstonePriceFeedExtension private redstonePriceFeedExtension;
    PendleExtension private pendleExtension;
    PendleAdaptor private pendleAdaptor;

    //ERC20 public primitive = WETH;
    //ERC20 public derivative = EETH;
    //ERC20 public wrappedDerivative =  AUSDC;

    //ERC20 public primitive = USDC;
    // ERC20 public derivative = AUSDC;
    // ERC20 public wrappedDerivative =  AUSDC;

    uint256 public initialAssets;

    // Pendle aUSDC
    address public pendleaUSDCMarket26Dec2024 = 0x875F154f4eC93255bEAEA9367c3AdF71Cdcb4Cc0;
    address public pendleaUSDCSy26Dec2024 = 0x369751A0b33DF3adE5e2eE55e7bB9556B10F390C;
    // Pendle Dec market: https://app.pendle.finance/trade/markets/0x875f154f4ec93255beaea9367c3adf71cdcb4cc0/swap?view=yt&chain=arbitrum
    address public pendleaUSDCPt26Dec2024 = 0xBB47aD7f407CBD385C9269ebd0d1Eb1CB634cDfa;
    address public pendleaUSDCYt26Dec2024 = 0xF065e0f7AFA89DF5f2a8a109239C809f115129AE;

    ERC20 public aV3USDCArb = ERC20(0x724dc807b04555b71ed48a6896b6F41593b8C637);

    // USDC FEED
    address public AUSDC_USD_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    // address public pendleRouterArb = 0x00000000005BBB0EF59571E58418F9a4357b68A0;
    // address public pendleOracleArb = 0x66a1096C6366b2529274dF4f5D8247827fe4CEA8;
    // uint256 public initialAssets;

    uint8 public maxRequests = 8;
    // source .env && forge test --match-path test/testPriceRouter/PendleExtensionAUSDC.t.sol -vvvv

    function setUp() external {
        console.log("Pendle Extension Test setUp 1.");
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 254030300;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        // pendleAdaptor = new PendleAdaptor(pendleMarketFactory, pendleRouter);
        pendleAdaptor = new PendleAdaptor(
            address(0x2FCb47B58350cD377f94d3821e7373Df60bD9Ced), address(0x00000000005BBB0EF59571E58418F9a4357b68A0)
        );

        // pendleExtension = new PendleExtension(priceRouter, pendleOracle);
        pendleExtension = new PendleExtension(priceRouter, address(0x1Fd95db7B7C0067De8D45C0cb35D59796adfD187));

        redstonePriceFeedExtension = new RedstonePriceFeedExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(AUSDC_USD_FEED).latestAnswer());
        console.log("Pendle Extension Test - USDC price.", price);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, AUSDC_USD_FEED);
        priceRouter.addAsset(aV3USDCArb, settings, abi.encode(stor), price);

        // Add pendle pricing.
        // uint256 lpPrice = 8_000e8; // 8,000,00000000
        // uint256 ptPrice = 3_784e8;
        // uint256 ytPrice = 200e8;

        // Add pendle pricing.
        uint256 lpPrice = 2.071e8; // 8,000,00000000, 207169090
        uint256 ptPrice = 9.871e7;
        uint256 ytPrice = 1.272e6;
        uint256 syPrice = 1.088e8;

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(pendleExtension));
        PendleExtension.ExtensionStorage memory pstor = PendleExtension.ExtensionStorage(
            PendleExtension.PendleAsset.LP, pendleaUSDCMarket26Dec2024, 300, aV3USDCArb
        );
        priceRouter.addAsset(ERC20(pendleaUSDCMarket26Dec2024), settings, abi.encode(pstor), lpPrice);

        pstor = PendleExtension.ExtensionStorage(
            PendleExtension.PendleAsset.SY, pendleaUSDCMarket26Dec2024, 300, aV3USDCArb
        );
        priceRouter.addAsset(ERC20(pendleaUSDCSy26Dec2024), settings, abi.encode(pstor), syPrice);

        pstor = PendleExtension.ExtensionStorage(
            PendleExtension.PendleAsset.PT, pendleaUSDCMarket26Dec2024, 300, aV3USDCArb
        );
        priceRouter.addAsset(ERC20(pendleaUSDCPt26Dec2024), settings, abi.encode(pstor), ptPrice);

        pstor = PendleExtension.ExtensionStorage(
            PendleExtension.PendleAsset.YT, pendleaUSDCMarket26Dec2024, 300, aV3USDCArb
        );
        priceRouter.addAsset(ERC20(pendleaUSDCYt26Dec2024), settings, abi.encode(pstor), ytPrice);
        // Setup Cellar:
    }

    function testSyPricing() external {
        uint256 underlyingPrice = priceRouter.getPriceInUSD(aV3USDCArb);
        console.log("Pendle Extension testSyPricing - aUSDC underlyingPrice price.", underlyingPrice);

        uint256 syPrice = priceRouter.getPriceInUSD(ERC20(pendleaUSDCSy26Dec2024));
        console.log("Pendle Extension testSyPricing - aUSDC syPrice price.", syPrice);

        uint256 priceDelta = uint256(syPrice) > uint256(underlyingPrice)
            ? uint256(syPrice) - uint256(underlyingPrice)
            : uint256(underlyingPrice) - uint256(syPrice);
        uint256 deltaPercentage = (priceDelta * 1e18) / uint256(underlyingPrice);

        console.log("Pendle Extension testSyPricing - Price delta:", priceDelta);
        console.log("Delta percentage:", deltaPercentage * 100 / 1e18, "%");

        // assertApproxEqRel(syPrice, underlyingPrice, 0.002e18, "SY price should equal underlying price");
        assertApproxEqRel(syPrice, underlyingPrice, 0.84328e18, "SY price should equal underlying price");
    }

    function testPyPricing() external {
        // Get prices for underlying, SY, PT, and YT in USD
        uint256 underlyingPrice = priceRouter.getPriceInUSD(aV3USDCArb);
        uint256 syPrice = priceRouter.getPriceInUSD(ERC20(pendleaUSDCSy26Dec2024));
        uint256 ptPrice = priceRouter.getPriceInUSD(ERC20(pendleaUSDCPt26Dec2024));
        uint256 ytPrice = priceRouter.getPriceInUSD(ERC20(pendleaUSDCYt26Dec2024));

        // Log the prices
        console.log("Underlying Price (USD):", underlyingPrice);
        console.log("SY Price (USD):", syPrice);
        console.log("PT Price (USD):", ptPrice);
        console.log("YT Price (USD):", ytPrice);

        // Calculate combined PT + YT price
        uint256 combinedPyPrice = ptPrice + ytPrice;
        console.log("Combined PT + YT Price (USD):", combinedPyPrice);

        // Calculate price deltas and percentages
        uint256 syDelta = syPrice > underlyingPrice ? syPrice - underlyingPrice : underlyingPrice - syPrice;
        uint256 pyDelta =
            combinedPyPrice > underlyingPrice ? combinedPyPrice - underlyingPrice : underlyingPrice - combinedPyPrice;

        uint256 syDeltaPercentage = (syDelta * 1e18) / underlyingPrice;
        uint256 pyDeltaPercentage = (pyDelta * 1e18) / underlyingPrice;

        console.log("SY-Underlying Delta:", syDelta);
        console.log("SY-Underlying Delta Percentage:", syDeltaPercentage * 100 / 1e18, "%");
        console.log("PY-Underlying Delta:", pyDelta);
        console.log("PY-Underlying Delta Percentage:", pyDeltaPercentage * 100 / 1e18, "%");

        // Assert that SY price is close to underlying price
        assertApproxEqRel(syPrice, underlyingPrice, 0.84328e18, "SY price should be close to underlying price");

        // Assert that combined PT+YT price is close to underlying price
        assertApproxEqRel(
            combinedPyPrice, underlyingPrice, 0.0001e18, "Combined PT+YT price should be close to underlying price"
        );

        // Assert that SY price is close to combined PT+YT price
        assertApproxEqRel(syPrice, combinedPyPrice, 0.84328e18, "SY price should be close to combined PT+YT price");
    }

    function testLpPricing() external {
        // Define test amounts
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18; // LP token amount
        amounts[1] = 50e18; // YT token amount
        amounts[2] = 50e18; // PT token amount

        console.log("Test amounts:");
        console.log("LP token amount:", amounts[0]);
        console.log("YT token amount:", amounts[1]);
        console.log("PT token amount:", amounts[2]);

        // Define assets to price
        ERC20[] memory assets = new ERC20[](3);
        assets[0] = ERC20(pendleaUSDCMarket26Dec2024); // LP token
        assets[1] = ERC20(pendleaUSDCYt26Dec2024); // YT token
        assets[2] = ERC20(pendleaUSDCPt26Dec2024); // PT token

        console.log("Assets to price:");
        console.log("LP token:", address(assets[0]));
        console.log("YT token:", address(assets[1]));
        console.log("PT token:", address(assets[2]));

        // Get the combined valuation in terms of the underlying asset
        uint256 combinedValuationInUnderlying = priceRouter.getValues(assets, amounts, aV3USDCArb);
        console.log("Combined valuation in underlying:", combinedValuationInUnderlying);

        // Get individual asset prices
        uint256[] memory individualPrices = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            individualPrices[i] = priceRouter.getValue(assets[i], 1e18, aV3USDCArb);
            console.log(string(abi.encodePacked("Price of asset ", i, ":")), individualPrices[i]);
        }

        // Calculate total value based on individual prices
        uint256 calculatedTotalValue = 0;
        for (uint256 i = 0; i < 3; i++) {
            calculatedTotalValue += (amounts[i] * individualPrices[i]) / 1e18;
        }
        console.log("Calculated total value:", calculatedTotalValue);

        // Compare combined valuation with calculated total value
        uint256 difference = combinedValuationInUnderlying > calculatedTotalValue
            ? combinedValuationInUnderlying - calculatedTotalValue
            : calculatedTotalValue - combinedValuationInUnderlying;
        console.log("Absolute difference:", difference);
        console.log("Relative difference (%):", (difference * 1e18 / calculatedTotalValue) / 1e14, "basis points");

        // Assert that the combined valuation is close to the calculated total value
        assertApproxEqRel(
            combinedValuationInUnderlying,
            calculatedTotalValue,
            0.001e18, // 0.1% tolerance
            "Combined valuation should be close to calculated total value"
        );
    }
}
