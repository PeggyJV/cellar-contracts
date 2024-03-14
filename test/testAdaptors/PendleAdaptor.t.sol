// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {
    EtherFiStakingAdaptor,
    StakingAdaptor,
    IWithdrawRequestNft,
    ILiquidityPool
} from "src/modules/adaptors/Staking/EtherFiStakingAdaptor.sol";
import {CellarWithNativeSupport} from "src/base/permutations/CellarWithNativeSupport.sol";
import {RedstonePriceFeedExtension} from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import {IRedstoneAdapter} from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import {PendleAdaptor, TokenInput, TokenOutput} from "src/modules/adaptors/Pendle/PendleAdaptor.sol";
import {PendleExtension} from "src/modules/price-router/Extensions/Pendle/PendleExtension.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SwapData, SwapType} from "@pendle/contracts/router/swap-aggregator/IPSwapAggregator.sol";
import {IRateProvider} from "src/interfaces/external/IRateProvider.sol";
import {ApproxParams} from "@pendle/contracts/router/base/MarketApproxLib.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import {AdaptorHelperFunctions} from "test/resources/AdaptorHelperFunctions.sol";

contract PendleAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address payable;

    EtherFiStakingAdaptor private etherFiAdaptor;
    CellarWithNativeSupport private cellar;
    RedstonePriceFeedExtension private redstonePriceFeedExtension;
    PendleAdaptor private pendleAdaptor;
    PendleExtension private pendleExtension;

    uint32 public wethPosition = 1;
    uint32 public eethPosition = 2;
    uint32 public weethPosition = 3;
    uint32 public etherFiPosition = 4;
    uint32 public pendleSYEethPosition = 5;
    uint32 public pendlePTEethPosition = 6;
    uint32 public pendleYTEethPosition = 7;
    uint32 public pendleLPEethPosition = 8;

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

        etherFiAdaptor = new EtherFiStakingAdaptor(
            address(WETH), 8, liquidityPool, withdrawalRequestNft, address(WEETH), address(EETH)
        );
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

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(etherFiAdaptor));
        registry.trustAdaptor(address(pendleAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(eethPosition, address(erc20Adaptor), abi.encode(EETH));
        registry.trustPosition(weethPosition, address(erc20Adaptor), abi.encode(WEETH));
        registry.trustPosition(pendleLPEethPosition, address(erc20Adaptor), abi.encode(pendleWeETHMarket));
        registry.trustPosition(pendleSYEethPosition, address(erc20Adaptor), abi.encode(pendleWeethSy));
        registry.trustPosition(pendlePTEethPosition, address(erc20Adaptor), abi.encode(pendleEethPt));
        registry.trustPosition(pendleYTEethPosition, address(erc20Adaptor), abi.encode(pendleEethYt));
        registry.trustPosition(etherFiPosition, address(etherFiAdaptor), abi.encode(primitive));

        string memory cellarName = "EtherFi Cellar V0.0";
        uint256 initialDeposit = 0.0001e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellarWithNativeSupport(
            cellarName, WETH, wethPosition, abi.encode(true), initialDeposit, platformCut
        );

        cellar.addAdaptorToCatalogue(address(etherFiAdaptor));
        cellar.addAdaptorToCatalogue(address(pendleAdaptor));

        cellar.addPositionToCatalogue(weethPosition);
        cellar.addPositionToCatalogue(eethPosition);
        cellar.addPositionToCatalogue(etherFiPosition);
        cellar.addPositionToCatalogue(pendleLPEethPosition);
        cellar.addPositionToCatalogue(pendleSYEethPosition);
        cellar.addPositionToCatalogue(pendlePTEethPosition);
        cellar.addPositionToCatalogue(pendleYTEethPosition);
        cellar.addPosition(1, weethPosition, abi.encode(true), false);
        cellar.addPosition(2, etherFiPosition, abi.encode(0), false);
        cellar.addPosition(3, eethPosition, abi.encode(0), false);
        cellar.addPosition(4, pendleLPEethPosition, abi.encode(false), false);
        cellar.addPosition(5, pendleSYEethPosition, abi.encode(false), false);
        cellar.addPosition(6, pendlePTEethPosition, abi.encode(false), false);
        cellar.addPosition(7, pendleYTEethPosition, abi.encode(false), false);

        cellar.setRebalanceDeviation(0.003e18);

        initialAssets = initialDeposit;

        WETH.safeApprove(address(cellar), type(uint256).max);
        deal(address(WETH), address(this), 1_000e18);
        cellar.deposit(1_000e18, address(this));
    }

    function testMintSyFromToken(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        assertEq(ERC20(pendleWeethSy).balanceOf(address(cellar)), amount, "Should have minted SY tokens to cellar");
    }

    function testMintPyFromSy(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount);

        uint256 expectedAmount = IRateProvider(address(WEETH)).getRate().mulDivDown(amount, 1e18);

        assertEq(
            ERC20(pendleEethPt).balanceOf(address(cellar)), expectedAmount, "Should have minted PT tokens to cellar"
        );
        assertEq(
            ERC20(pendleEethYt).balanceOf(address(cellar)), expectedAmount, "Should have minted YT tokens to cellar"
        );
    }

    function testSwapExactPtForYt(uint256 amount) external {
        // Note lower max amount, I think this is do from slippage cuz we have to do ALOT of swapping in the pool.
        amount = bound(amount, 0.01e18, 50e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount, 1e18);

        ApproxParams memory approxParams = ApproxParams(0, type(uint256).max, 0, 256, 0.001e18);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToSwapExactPtForYt(pendleWeETHMarket, pyBalance, 0, approxParams);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertEq(ERC20(pendleEethPt).balanceOf(address(cellar)), 0, "Should have sold all PT tokens");
        assertGt(ERC20(pendleEethYt).balanceOf(address(cellar)), pyBalance, "Should have more YT tokens than before");
    }

    function testSwapExactYtForPt(uint256 amount) external {
        // Note lower max amount, I think this is do from slippage cuz we have to do ALOT of swapping in the pool.
        amount = bound(amount, 0.01e18, 100e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount, 1e18);

        ApproxParams memory approxParams = ApproxParams(0, type(uint256).max, 0, 256, 0.001e18);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToSwapExactYtForPt(pendleWeETHMarket, pyBalance, 0, approxParams);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertEq(ERC20(pendleEethYt).balanceOf(address(cellar)), 0, "Should have sold all YT tokens");
        assertGt(ERC20(pendleEethPt).balanceOf(address(cellar)), pyBalance, "Should have more PT tokens than before");
    }

    function testAddLiquidityWithSyAndPt(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount / 2);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount / 2, 1e18);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddLiquidityDualSyAndPt(pendleWeETHMarket, amount / 2, pyBalance, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertGt(ERC20(pendleWeETHMarket).balanceOf(address(cellar)), 0, "Should have minted LP tokens");
    }

    function testRemoveLiquidityDualSyAndPt(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount / 2);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount / 2, 1e18);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddLiquidityDualSyAndPt(pendleWeETHMarket, amount / 2, pyBalance, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        uint256 lpBalance = ERC20(pendleWeETHMarket).balanceOf(address(cellar));

        adaptorCalls[0] = _createBytesDataToRemoveLiquidityDualSyAndPt(pendleWeETHMarket, lpBalance, 0, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertEq(ERC20(pendleWeETHMarket).balanceOf(address(cellar)), 0, "Should have burned all LP tokens");
        assertApproxEqAbs(
            ERC20(pendleEethPt).balanceOf(address(cellar)), 10, pyBalance, "Should have received PT back."
        );
        assertApproxEqAbs(
            ERC20(pendleWeethSy).balanceOf(address(cellar)), amount / 2, 10, "Should have received SY back."
        );
    }

    function testRedeemPyToSy(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount, 1e18);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRedeemPyToSy(pendleWeETHMarket, pyBalance, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(ERC20(pendleWeethSy).balanceOf(address(cellar)), amount, 10, "Should have received SY tokens");
    }

    function testRedeemSyToToken(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount, 1e18);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRedeemPyToSy(pendleWeETHMarket, pyBalance, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        uint256 syBalance = ERC20(pendleWeethSy).balanceOf(address(cellar));

        SwapData memory swapData;
        TokenOutput memory output = TokenOutput(address(WEETH), 0, address(WEETH), address(0), swapData);
        adaptorCalls[0] = _createBytesDataToRedeemSyToToken(pendleWeETHMarket, syBalance, output);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(WEETH.balanceOf(address(cellar)), amount, 10, "Should have received weETH tokens back");
    }

    //============================================ Max Available Tests ===========================================

    function testMintSyFromTokenWithMaxAvailable(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000e18);
        // Mint some SY tokens from weETH.
        deal(address(WEETH), address(cellar), amount);
        SwapData memory swapData;
        TokenInput memory input = TokenInput(address(WEETH), type(uint256).max, address(WEETH), address(0), swapData);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMintSyFromToken(pendleWeETHMarket, 0, input);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertEq(ERC20(pendleWeethSy).balanceOf(address(cellar)), amount, "Should have minted SY tokens to cellar");
    }

    function testMintPyFromSyWithMaxAvailable(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(type(uint256).max);

        uint256 expectedAmount = IRateProvider(address(WEETH)).getRate().mulDivDown(amount, 1e18);

        assertEq(
            ERC20(pendleEethPt).balanceOf(address(cellar)), expectedAmount, "Should have minted PT tokens to cellar"
        );
        assertEq(
            ERC20(pendleEethYt).balanceOf(address(cellar)), expectedAmount, "Should have minted YT tokens to cellar"
        );
    }

    function testSwapExactPtForYtWithMaxAvailable(uint256 amount) external {
        // Note lower max amount, I think this is do from slippage cuz we have to do ALOT of swapping in the pool.
        amount = bound(amount, 0.01e18, 50e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount, 1e18);

        ApproxParams memory approxParams = ApproxParams(0, type(uint256).max, 0, 256, 0.001e18);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToSwapExactPtForYt(pendleWeETHMarket, type(uint256).max, 0, approxParams);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertEq(ERC20(pendleEethPt).balanceOf(address(cellar)), 0, "Should have sold all PT tokens");
        assertGt(ERC20(pendleEethYt).balanceOf(address(cellar)), pyBalance, "Should have more YT tokens than before");
    }

    function testSwapExactYtForPtWithMaxAvailable(uint256 amount) external {
        // Note lower max amount, I think this is do from slippage cuz we have to do ALOT of swapping in the pool.
        amount = bound(amount, 0.01e18, 100e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount, 1e18);

        ApproxParams memory approxParams = ApproxParams(0, type(uint256).max, 0, 256, 0.001e18);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToSwapExactYtForPt(pendleWeETHMarket, type(uint256).max, 0, approxParams);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertEq(ERC20(pendleEethYt).balanceOf(address(cellar)), 0, "Should have sold all YT tokens");
        assertGt(ERC20(pendleEethPt).balanceOf(address(cellar)), pyBalance, "Should have more PT tokens than before");
    }

    function testAddLiquidityWithSyAndPtWithMaxAvailable(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount / 2);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] =
            _createBytesDataToAddLiquidityDualSyAndPt(pendleWeETHMarket, type(uint256).max, type(uint256).max, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertGt(ERC20(pendleWeETHMarket).balanceOf(address(cellar)), 0, "Should have minted LP tokens");
    }

    function testRemoveLiquidityDualSyAndPtWithMaxAvailable(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount / 2);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount / 2, 1e18);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddLiquidityDualSyAndPt(pendleWeETHMarket, amount / 2, pyBalance, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToRemoveLiquidityDualSyAndPt(pendleWeETHMarket, type(uint256).max, 0, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertEq(ERC20(pendleWeETHMarket).balanceOf(address(cellar)), 0, "Should have burned all LP tokens");
        assertApproxEqAbs(
            ERC20(pendleEethPt).balanceOf(address(cellar)), 10, pyBalance, "Should have received PT back."
        );
        assertApproxEqAbs(
            ERC20(pendleWeethSy).balanceOf(address(cellar)), amount / 2, 10, "Should have received SY back."
        );
    }

    function testRedeemPyToSyWithMaxAvailable(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRedeemPyToSy(pendleWeETHMarket, type(uint256).max, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(ERC20(pendleWeethSy).balanceOf(address(cellar)), amount, 10, "Should have received SY tokens");
    }

    function testRedeemSyToTokenWithMaxAvailable(uint256 amount) external {
        amount = bound(amount, 0.01e18, 1_000_000e18);
        // Mint some SY tokens from weETH.
        _mintSyWithToken(WEETH, amount);

        // Mint some PT and YT using SY.
        _mintPyWithSy(amount);

        uint256 pyBalance = IRateProvider(address(WEETH)).getRate().mulDivDown(amount, 1e18);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRedeemPyToSy(pendleWeETHMarket, pyBalance, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        SwapData memory swapData;
        TokenOutput memory output = TokenOutput(address(WEETH), 0, address(WEETH), address(0), swapData);
        adaptorCalls[0] = _createBytesDataToRedeemSyToToken(pendleWeETHMarket, type(uint256).max, output);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(WEETH.balanceOf(address(cellar)), amount, 10, "Should have received weETH tokens back");
    }

    //============================================ Revert Tests ===========================================

    function testVerifyMarketRevert() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        address fakeMarket = vm.addr(420);
        TokenInput memory input;
        TokenOutput memory output;
        ApproxParams memory approxParams;

        adaptorCalls[0] = _createBytesDataToMintSyFromToken(fakeMarket, 0, input);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__BadMarket.selector)));
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToMintPyFromSy(fakeMarket, 0, 0);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__BadMarket.selector)));
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToSwapExactPtForYt(fakeMarket, 0, 0, approxParams);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__BadMarket.selector)));
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToSwapExactYtForPt(fakeMarket, 0, 0, approxParams);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__BadMarket.selector)));
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToAddLiquidityDualSyAndPt(fakeMarket, 0, 0, 0);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__BadMarket.selector)));
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToRemoveLiquidityDualSyAndPt(fakeMarket, 0, 0, 0);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__BadMarket.selector)));
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToRedeemPyToSy(fakeMarket, 0, 0);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__BadMarket.selector)));
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToRedeemSyToToken(fakeMarket, 0, output);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__BadMarket.selector)));
        cellar.callOnAdaptor(data);
    }

    function testDexAggregatorReverts() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        address fakePendleSwapAddress = vm.addr(1);
        address fakeExtRouterAddress = vm.addr(2);

        SwapData memory swapData =
            SwapData({swapType: SwapType.NONE, extRouter: address(0), extCalldata: hex"", needScale: false});
        TokenInput memory input = TokenInput({
            tokenIn: address(WEETH),
            netTokenIn: 0,
            tokenMintSy: address(WEETH),
            pendleSwap: address(0),
            swapData: swapData
        });
        TokenOutput memory output = TokenOutput({
            tokenOut: address(WEETH),
            minTokenOut: 0,
            tokenRedeemSy: address(WEETH),
            pendleSwap: address(0),
            swapData: swapData
        });
        // Change tokenIn.
        input.tokenIn = address(WETH);
        adaptorCalls[0] = _createBytesDataToMintSyFromToken(pendleWeETHMarket, 0, input);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__UseAggregatorToSwap.selector)));
        cellar.callOnAdaptor(data);

        // Fix tokenIn but change pendleSwap to fake address.
        input.tokenIn = address(WEETH);
        input.pendleSwap = fakePendleSwapAddress;
        adaptorCalls[0] = _createBytesDataToMintSyFromToken(pendleWeETHMarket, 0, input);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__UseAggregatorToSwap.selector)));
        cellar.callOnAdaptor(data);

        // Fix pendleSwap but change extRouter
        input.pendleSwap = address(0);
        input.swapData.extRouter = fakeExtRouterAddress;
        adaptorCalls[0] = _createBytesDataToMintSyFromToken(pendleWeETHMarket, 0, input);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__UseAggregatorToSwap.selector)));
        cellar.callOnAdaptor(data);

        // Fix extRouter but change swapType to not NONE.
        input.swapData.extRouter = address(0);
        input.swapData.swapType = SwapType.ONE_INCH;
        adaptorCalls[0] = _createBytesDataToMintSyFromToken(pendleWeETHMarket, 0, input);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__UseAggregatorToSwap.selector)));
        cellar.callOnAdaptor(data);

        // Change tokenOut
        output.tokenOut = address(WETH);
        adaptorCalls[0] = _createBytesDataToRedeemSyToToken(pendleWeETHMarket, 0, output);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__UseAggregatorToSwap.selector)));
        cellar.callOnAdaptor(data);

        // Fix tokenOut but change pendleSwap to fake address.
        output.tokenOut = address(WEETH);
        output.pendleSwap = fakePendleSwapAddress;
        adaptorCalls[0] = _createBytesDataToRedeemSyToToken(pendleWeETHMarket, 0, output);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__UseAggregatorToSwap.selector)));
        cellar.callOnAdaptor(data);

        // Fix pendleSwap but change extRouter
        output.pendleSwap = address(0);
        output.swapData.extRouter = fakeExtRouterAddress;
        adaptorCalls[0] = _createBytesDataToRedeemSyToToken(pendleWeETHMarket, 0, output);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__UseAggregatorToSwap.selector)));
        cellar.callOnAdaptor(data);

        // Fix extRouter but change swapType to not NONE.
        output.swapData.extRouter = address(0);
        output.swapData.swapType = SwapType.ONE_INCH;
        adaptorCalls[0] = _createBytesDataToRedeemSyToToken(pendleWeETHMarket, 0, output);
        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        vm.expectRevert(bytes(abi.encodeWithSelector(PendleAdaptor.PendleAdaptor__UseAggregatorToSwap.selector)));
        cellar.callOnAdaptor(data);
    }

    //============================================ Helper Functions ===========================================

    function _mintSyWithToken(ERC20 token, uint256 amount) internal {
        deal(address(token), address(cellar), amount);
        SwapData memory swapData;
        TokenInput memory input = TokenInput(address(token), amount, address(token), address(0), swapData);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMintSyFromToken(pendleWeETHMarket, 0, input);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);
    }

    function _mintPyWithSy(uint256 amount) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMintPyFromSy(pendleWeETHMarket, amount, 0);

        data[0] = Cellar.AdaptorCall({adaptor: address(pendleAdaptor), callData: adaptorCalls});
        cellar.callOnAdaptor(data);
    }

    function _createCellarWithNativeSupport(
        string memory cellarName,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithNativeSupport) {
        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(holdingAsset), address(this), initialDeposit);
        holdingAsset.approve(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithNativeSupport).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            holdingAsset,
            cellarName,
            cellarName,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        return CellarWithNativeSupport(payable(deployer.deployContract(cellarName, creationCode, constructorArgs, 0)));
    }
}
