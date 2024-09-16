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

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

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

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(pendleExtension));
        PendleExtension.ExtensionStorage memory pstor = PendleExtension.ExtensionStorage(
            PendleExtension.PendleAsset.LP, pendleaUSDCMarket26Dec2024, 300, aV3USDCArb
        );
        priceRouter.addAsset(ERC20(pendleaUSDCMarket26Dec2024), settings, abi.encode(pstor), lpPrice);

        //pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.SY, pendleaUSDCMarket26Dec2024, 300, EETH);
        //priceRouter.addAsset(ERC20( pendleaUSDCSy26Dec2024), settings, abi.encode(pstor), priceRouter.getPriceInUSD( AUSDC));

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
        uint256 syPrice = priceRouter.getPriceInUSD(ERC20(pendleaUSDCSy26Dec2024));

        assertApproxEqRel(syPrice, underlyingPrice, 0.002e18, "SY price should equal underlying price");
    }

    function testPyPricing(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000e18);
        deal(address(aV3USDCArb), address(this), amount);

        // Exchange  AUSDC for SY
        SwapData memory swapData;
        TokenInput memory input = TokenInput(address(aV3USDCArb), amount, address(aV3USDCArb), address(0), swapData);
        bytes memory callData = _createBytesDataToMintSyFromToken(pendleaUSDCMarket26Dec2024, 0, input);
        address(pendleAdaptor).functionDelegateCall(callData);

        // Exchange SY for PT and YT.
        callData = _createBytesDataToMintPyFromSy(pendleaUSDCMarket26Dec2024, amount, 0);
        address(pendleAdaptor).functionDelegateCall(callData);

        ERC20[] memory baseAssets = new ERC20[](2);
        baseAssets[0] = ERC20(pendleaUSDCPt26Dec2024);
        baseAssets[1] = ERC20(pendleaUSDCYt26Dec2024);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ERC20(pendleaUSDCPt26Dec2024).balanceOf(address(this));
        amounts[1] = ERC20(pendleaUSDCYt26Dec2024).balanceOf(address(this));
        uint256 pyValuationInUnderlying = priceRouter.getValues(baseAssets, amounts, aV3USDCArb);

        assertApproxEqRel(pyValuationInUnderlying, amount, 0.002e18, "Combined PT and YT value should equal value in.");
    }

    function testLpPricing(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000e18);
        deal(address(aV3USDCArb), address(this), amount);

        // Exchange  AUSDC for SY
        SwapData memory swapData;
        TokenInput memory input = TokenInput(address(aV3USDCArb), amount, address(aV3USDCArb), address(0), swapData);
        bytes memory callData = _createBytesDataToMintSyFromToken(pendleaUSDCMarket26Dec2024, 0, input);
        address(pendleAdaptor).functionDelegateCall(callData);

        // Exchange SY for PT and YT.
        callData = _createBytesDataToMintPyFromSy(pendleaUSDCMarket26Dec2024, amount / 2, 0);
        address(pendleAdaptor).functionDelegateCall(callData);

        // Exchange PT and SY for LP.
        callData = _createBytesDataToAddLiquidityDualSyAndPt(
            pendleaUSDCMarket26Dec2024, type(uint256).max, type(uint256).max, 0
        );
        address(pendleAdaptor).functionDelegateCall(callData);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = ERC20(pendleaUSDCMarket26Dec2024);
        baseAssets[1] = ERC20(pendleaUSDCYt26Dec2024);
        baseAssets[2] = ERC20(pendleaUSDCPt26Dec2024);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = ERC20(pendleaUSDCMarket26Dec2024).balanceOf(address(this));
        amounts[1] = ERC20(pendleaUSDCYt26Dec2024).balanceOf(address(this));
        amounts[2] = ERC20(pendleaUSDCPt26Dec2024).balanceOf(address(this));
        uint256 combinedValuationInUnderlying = priceRouter.getValues(baseAssets, amounts, aV3USDCArb);

        assertApproxEqRel(
            combinedValuationInUnderlying, amount, 0.002e18, "Combined LP , PT, and YT value should equal value in."
        );
    }

    //============================================ Revert Tests ===========================================
    /*
    function testSetupSourceReverts() external {
        PriceRouter.AssetSettings memory settings;
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(pendleExtension));
        PendleExtension.ExtensionStorage memory pstor =
            PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.LP, pendleSwethMarket, 300, SWETH);
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PendleExtension.PendleExtension__UNDERLYING_NOT_SUPPORTED.selector))
        );
        priceRouter.addAsset(ERC20(pendleSwethMarket), settings, abi.encode(pstor), 0);

        // Add SWETH pricing.
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(SWETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(pendleExtension));
        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.LP, pendleSwethMarket, 86_400, SWETH);
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleExtension.PendleExtension__ORACLE_NOT_READY.selector)));
        priceRouter.addAsset(ERC20(pendleSwethMarket), settings, abi.encode(pstor), 0);
    }
    */
}
