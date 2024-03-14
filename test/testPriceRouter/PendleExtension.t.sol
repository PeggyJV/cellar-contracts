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

    ERC20 public primitive = WETH;
    ERC20 public derivative = EETH;
    ERC20 public wrappedDerivative = WEETH;

    uint256 public initialAssets;

    uint8 public maxRequests = 8;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19428610;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        pendleAdaptor = new PendleAdaptor(pendleMarketFactory, pendleRouter);

        pendleExtension = new PendleExtension(priceRouter, pendleOracle);

        redstonePriceFeedExtension = new RedstonePriceFeedExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Set eETH to be 1:1 with wETH.
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(EETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));
        RedstonePriceFeedExtension.ExtensionStorage memory rstor;
        rstor.dataFeedId = weethUsdDataFeedId;
        rstor.heartbeat = 1 days;
        rstor.redstoneAdapter = IRedstoneAdapter(weethAdapter);
        price = IRedstoneAdapter(weethAdapter).getValueForDataFeed(rstor.dataFeedId);
        priceRouter.addAsset(WEETH, settings, abi.encode(rstor), price);

        // Add pendle pricing.
        uint256 lpPrice = 8_000e8;
        uint256 ptPrice = 3_784e8;
        uint256 ytPrice = 200e8;

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(pendleExtension));
        PendleExtension.ExtensionStorage memory pstor =
            PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.LP, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleWeETHMarket), settings, abi.encode(pstor), lpPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.SY, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleWeethSy), settings, abi.encode(pstor), priceRouter.getPriceInUSD(WEETH));

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.PT, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethPt), settings, abi.encode(pstor), ptPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.YT, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethYt), settings, abi.encode(pstor), ytPrice);
        // Setup Cellar:
    }

    function testSyPricing() external {
        uint256 underlyingPrice = priceRouter.getPriceInUSD(WEETH);
        uint256 syPrice = priceRouter.getPriceInUSD(ERC20(pendleWeethSy));

        assertApproxEqRel(syPrice, underlyingPrice, 0.002e18, "SY price should equal underlying price");
    }

    function testPyPricing(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000e18);
        deal(address(WEETH), address(this), amount);

        // Exchange WEETH for SY
        SwapData memory swapData;
        TokenInput memory input = TokenInput(address(WEETH), amount, address(WEETH), address(0), swapData);
        bytes memory callData = _createBytesDataToMintSyFromToken(pendleWeETHMarket, 0, input);
        address(pendleAdaptor).functionDelegateCall(callData);

        // Exchange SY for PT and YT.
        callData = _createBytesDataToMintPyFromSy(pendleWeETHMarket, amount, 0);
        address(pendleAdaptor).functionDelegateCall(callData);

        ERC20[] memory baseAssets = new ERC20[](2);
        baseAssets[0] = ERC20(pendleEethPt);
        baseAssets[1] = ERC20(pendleEethYt);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ERC20(pendleEethPt).balanceOf(address(this));
        amounts[1] = ERC20(pendleEethYt).balanceOf(address(this));
        uint256 pyValuationInUnderlying = priceRouter.getValues(baseAssets, amounts, WEETH);

        assertApproxEqRel(pyValuationInUnderlying, amount, 0.002e18, "Combined PT and YT value should equal value in.");
    }

    function testLpPricing(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000e18);
        deal(address(WEETH), address(this), amount);

        // Exchange WEETH for SY
        SwapData memory swapData;
        TokenInput memory input = TokenInput(address(WEETH), amount, address(WEETH), address(0), swapData);
        bytes memory callData = _createBytesDataToMintSyFromToken(pendleWeETHMarket, 0, input);
        address(pendleAdaptor).functionDelegateCall(callData);

        // Exchange SY for PT and YT.
        callData = _createBytesDataToMintPyFromSy(pendleWeETHMarket, amount / 2, 0);
        address(pendleAdaptor).functionDelegateCall(callData);

        // Exchange PT and SY for LP.
        callData = _createBytesDataToAddLiquidityDualSyAndPt(pendleWeETHMarket, type(uint256).max, type(uint256).max, 0);
        address(pendleAdaptor).functionDelegateCall(callData);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = ERC20(pendleWeETHMarket);
        baseAssets[1] = ERC20(pendleEethYt);
        baseAssets[2] = ERC20(pendleEethPt);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = ERC20(pendleWeETHMarket).balanceOf(address(this));
        amounts[1] = ERC20(pendleEethYt).balanceOf(address(this));
        amounts[2] = ERC20(pendleEethPt).balanceOf(address(this));
        uint256 combinedValuationInUnderlying = priceRouter.getValues(baseAssets, amounts, WEETH);

        assertApproxEqRel(
            combinedValuationInUnderlying, amount, 0.002e18, "Combined LP , PT, and YT value should equal value in."
        );
    }

    //============================================ Revert Tests ===========================================

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
}
