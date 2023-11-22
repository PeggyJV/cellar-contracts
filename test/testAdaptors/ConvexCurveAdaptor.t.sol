// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { ConvexCurveAdaptor } from "src/modules/adaptors/Convex/ConvexCurveAdaptor.sol";
import { IBaseRewardPool } from "src/interfaces/external/Convex/IBaseRewardPool.sol";
import { IBooster } from "src/interfaces/external/Convex/IBooster.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

/// CRISPY imports

import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { CurveEMAExtension } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";
import { Curve2PoolExtension } from "src/modules/price-router/Extensions/Curve/Curve2PoolExtension.sol";
import { CurvePool } from "src/interfaces/external/Curve/CurvePool.sol";
import { MockCellarWithOracle } from "src/mocks/MockCellarWithOracle.sol";

/// CRISPY Pricing imports above copied over (TODO: delete your copy of his imported files (`WstEthExtension.sol, CurveEMAExtension.sol, Curve2PoolExtension.sol`) and `git pull` his actual files from dev branch ONCE he's merged his changes to it).

/**
 * @title ConvexCurveAdaptorTest
 * @author crispymangoes, 0xEinCodes
 * @notice Cellar Adaptor tests with Convex-Curve markets
 */
contract ConvexCurveAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    Cellar public cellar;

    // from convex (for curve markets)
    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    ConvexCurveAdaptor private convexCurveAdaptor;
    IBooster public immutable booster = IBooster(convexCurveMainnetBooster);
    IBaseRewardPool public rewardsPool; // varies per convex market

    WstEthExtension private wstethExtension;
    CurveEMAExtension private curveEMAExtension;
    Curve2PoolExtension private curve2PoolExtension;

    MockDataFeed public mockWETHdataFeed;
    MockDataFeed public mockUSDCdataFeed;
    MockDataFeed public mockDAI_dataFeed;
    MockDataFeed public mockUSDTdataFeed;
    MockDataFeed public mockFRAXdataFeed;
    MockDataFeed public mockSTETHdataFeed;
    MockDataFeed public mockRETHdataFeed;

    // erc20 positions for base constituent ERC20s
    uint32 private usdcPosition = 1;
    uint32 private crvusdPosition = 2;
    uint32 private wethPosition = 3;
    uint32 private stethPosition = 4;
    uint32 private fraxPosition = 5;
    uint32 private frxethPosition = 6;
    uint32 private cvxPosition = 7;
    uint32 private mkUsdPosition = 8;
    uint32 private yethPosition = 9;
    uint32 private ethXPosition = 10;
    uint32 private sFraxPosition = 11;

    // ConvexCurveAdaptor Positions
    uint32 private EthFrxethPoolPosition = 12; // https://www.convexfinance.com/stake/ethereum/128
    uint32 private EthStethNgPoolPosition = 13;
    uint32 private fraxCrvUsdPoolPosition = 14;
    uint32 private mkUsdFraxUsdcPoolPosition = 15;
    uint32 private WethYethPoolPosition = 16;
    uint32 private EthEthxPoolPosition = 17;
    uint32 private CrvUsdSfraxPoolPosition = 18;

    // erc20 positions for Curve LPTs
    uint32 private EthFrxethERC20Position = 19;
    uint32 private EthStethNgERC20Position = 20;
    uint32 private fraxCrvUsdERC20Position = 21;
    uint32 private mkUsdFraxUsdcERC20Position = 22;
    uint32 private WethYethERC20Position = 23;
    uint32 private EthEthxERC20Position = 24;
    uint32 private CrvUsdSfraxERC20Position = 25;

    uint32 private slippage = 0.9e4;
    uint256 public initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18538479;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockWETHdataFeed = new MockDataFeed(WETH_USD_FEED);
        mockUSDCdataFeed = new MockDataFeed(USDC_USD_FEED);
        mockDAI_dataFeed = new MockDataFeed(DAI_USD_FEED);
        mockUSDTdataFeed = new MockDataFeed(USDT_USD_FEED);
        mockFRAXdataFeed = new MockDataFeed(FRAX_USD_FEED);
        mockSTETHdataFeed = new MockDataFeed(STETH_USD_FEED);
        mockRETHdataFeed = new MockDataFeed(RETH_ETH_FEED);

        curveEMAExtension = new CurveEMAExtension(priceRouter, address(WETH), 18);
        curve2PoolExtension = new Curve2PoolExtension(priceRouter, address(WETH), 18);
        wstethExtension = new WstEthExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        // Add WETH pricing.
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWETHdataFeed));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Add USDC pricing.
        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUSDCdataFeed));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Add DAI pricing.
        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockDAI_dataFeed));
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // Add USDT pricing.
        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUSDTdataFeed));
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        // Add FRAX pricing.
        price = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockFRAXdataFeed));
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        // Add stETH pricing.
        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockSTETHdataFeed));
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        // Add wstEth pricing.
        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);

        // Add CrvUsd
        CurveEMAExtension.ExtensionStorage memory cStor;
        cStor.pool = UsdcCrvUsdPool;
        cStor.index = 0;
        cStor.needIndex = false;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(USDC), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(CRVUSD, settings, abi.encode(cStor), price);

        // Add FrxEth
        cStor.pool = WethFrxethPool;
        cStor.index = 0;
        cStor.needIndex = false;
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

        // Add mkUsd
        cStor.pool = WethMkUsdPool;
        cStor.index = 0;
        cStor.needIndex = false;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(MKUSD, settings, abi.encode(cStor), price);

        // Add yETH
        cStor.pool = WethYethPool;
        cStor.index = 0;
        cStor.needIndex = false;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(YETH, settings, abi.encode(cStor), price);

        // Add ETHx
        cStor.pool = EthEthxPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.handleRate = true;
        cStor.rateIndex = 1;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(ETHX, settings, abi.encode(cStor), price);

        // Add sFRAX
        cStor.pool = CrvUsdSfraxPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.handleRate = true;
        cStor.rateIndex = 1;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(FRAX), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(ERC20(sFRAX), settings, abi.encode(cStor), price);

        // CURVE MARKETS OF ITB INTEREST
        // stETH-ETH ng --> stETHWethNg
        // mkUSD-FRAXbp --> mkUsdFraxUsdcPool
        // yETH-ETH --> WethYethPool
        // ETHx-ETH --> EthEthxPool
        // frxETH-WETH
        // FRAX-crvUSD
        // frxETH-ETH

        // mkUsdFraxUsdcPool
        // mkUsdFraxUsdcToken
        // mkUsdFraxUsdcGauge
        _add2PoolAssetToPriceRouter(
            mkUsdFraxUsdcPool,
            mkUsdFraxUsdcToken,
            true,
            1e8,
            MKUSD,
            ERC20(FraxUsdcToken),
            false,
            false
        );

        // EthStethNgPool
        // EthStethNgToken
        // EthStethNgGauge
        _add2PoolAssetToPriceRouter(EthStethNgPool, EthStethNgToken, true, 1_800e8, WETH, STETH, false, false);

        // WethYethPool
        // WethYethToken
        // WethYethGauge
        _add2PoolAssetToPriceRouter(WethYethPool, WethYethToken, true, 1_800e8, WETH, YETH, false, false);
        // EthEthxPool
        // EthEthxToken
        // EthEthxGauge
        _add2PoolAssetToPriceRouter(EthEthxPool, EthEthxToken, true, 1_800e8, WETH, ETHX, false, true);

        // CrvUsdSfraxPool
        // CrvUsdSfraxToken
        // CrvUsdSfraxGauge
        _add2PoolAssetToPriceRouter(CrvUsdSfraxPool, CrvUsdSfraxToken, true, 1e8, CRVUSD, FRAX, false, false);

        // Likely going to be in the frax platform adaptor tests but will test here in case we need to go into the convex-curve platform tests

        // frxETH-WETH
        // FRAX-crvUSD
        // frxETH-ETH

        // WethFrxethPool
        // WethFrxethToken
        // WethFrxethGauge
        _add2PoolAssetToPriceRouter(WethFrxethPool, WethFrxethToken, true, 1800e8, WETH, FRXETH, false, false);
        // EthFrxethPool
        // EthFrxethToken
        // EthFrxethGauge
        _add2PoolAssetToPriceRouter(EthFrxethPool, EthFrxethToken, true, 1800e8, WETH, FRXETH, false, false);
        // FraxCrvUsdPool
        // FraxCrvUsdToken
        // FraxCrvUsdGauge
        _add2PoolAssetToPriceRouter(FraxCrvUsdPool, FraxCrvUsdToken, true, 1e8, FRAX, CRVUSD, false, false);

        convexCurveAdaptor = new ConvexCurveAdaptor(convexCurveMainnetBooster);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(convexCurveAdaptor));

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(crvusdPosition, address(erc20Adaptor), abi.encode(CRVUSD));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(stethPosition, address(erc20Adaptor), abi.encode(STETH));
        registry.trustPosition(fraxPosition, address(erc20Adaptor), abi.encode(FRAX));
        registry.trustPosition(frxethPosition, address(erc20Adaptor), abi.encode(FRXETH));
        registry.trustPosition(cvxPosition, address(erc20Adaptor), abi.encode(CVX));
        registry.trustPosition(mkUsdPosition, address(erc20Adaptor), abi.encode(MKUSD));
        registry.trustPosition(yethPosition, address(erc20Adaptor), abi.encode(YETH));
        registry.trustPosition(ethXPosition, address(erc20Adaptor), abi.encode(ETHX));
        // adaptorData = abi.encode(uint256 pid, address baseRewardPool)

        registry.trustPosition(
            EthFrxethPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(128, ethFrxethBaseRewardPool, EthFrxethToken, CurvePool(EthFrxethPool))
        );
        registry.trustPosition(
            EthStethNgPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(177, ethStethNgBaseRewardPool, EthStethNgToken, CurvePool(EthStethNgPool))
        );
        registry.trustPosition(
            fraxCrvUsdPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(187, fraxCrvUsdBaseRewardPool, FraxCrvUsdToken, CurvePool(FraxCrvUsdPool))
        );
        registry.trustPosition(
            mkUsdFraxUsdcPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(225, mkUsdFraxUsdcBaseRewardPool, mkUsdFraxUsdcToken, CurvePool(mkUsdFraxUsdcPool))
        );
        registry.trustPosition(
            WethYethPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(231, wethYethBaseRewardPool, WethYethToken, CurvePool(WethYethPool))
        );
        registry.trustPosition(
            EthEthxPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(232, ethEthxBaseRewardPool, EthEthxToken, CurvePool(EthEthxPool))
        );
        registry.trustPosition(
            CrvUsdSfraxPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(252, crvUsdSFraxBaseRewardPool, CrvUsdSfraxToken, CurvePool(CrvUsdSfraxPool))
        );

        // trust erc20 positions for curve lpts for this test file, although in actual implementation of the cellar there would be usage of a `CurveAdaptor` position for each respective curveLPT to track liquid LPTs that are not staked into Convex.
        registry.trustPosition(EthFrxethERC20Position, address(erc20Adaptor), abi.encode(ERC20(EthFrxethToken)));
        registry.trustPosition(EthStethNgERC20Position, address(erc20Adaptor), abi.encode(ERC20(EthStethNgToken)));
        registry.trustPosition(fraxCrvUsdERC20Position, address(erc20Adaptor), abi.encode(ERC20(FraxCrvUsdToken)));
        registry.trustPosition(
            mkUsdFraxUsdcERC20Position,
            address(erc20Adaptor),
            abi.encode(ERC20(mkUsdFraxUsdcToken))
        );
        registry.trustPosition(WethYethERC20Position, address(erc20Adaptor), abi.encode(ERC20(WethYethToken)));
        registry.trustPosition(EthEthxERC20Position, address(erc20Adaptor), abi.encode(ERC20(EthEthxToken)));
        registry.trustPosition(CrvUsdSfraxERC20Position, address(erc20Adaptor), abi.encode(ERC20(CrvUsdSfraxToken)));

        string memory cellarName = "Convex Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        // baseAsset is USDC, but we will deal out LPTs within the helper test function similar to CurveAdaptor.t.sol
        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);

        USDC.safeApprove(address(cellar), type(uint256).max);

        for (uint32 i = 2; i < 19; ++i) cellar.addPositionToCatalogue(i);
        for (uint32 i = 2; i < 19; ++i) cellar.addPosition(0, i, abi.encode(true), false);

        cellar.setRebalanceDeviation(0.01e18);

        cellar.addAdaptorToCatalogue(address(convexCurveAdaptor));

        initialAssets = cellar.totalAssets();
    }

    //============================================ Happy Path Tests ===========================================

    function testManagingVanillaCurveLPTs1(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(_assets, EthFrxethToken, 128, ethFrxethBaseRewardPool);
    }

    function testManagingVanillaCurveLPTs2(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(_assets, EthStethNgToken, 177, ethStethNgBaseRewardPool);
    }

    function testManagingVanillaCurveLPTs3(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(_assets, FraxCrvUsdToken, 187, fraxCrvUsdBaseRewardPool);
    }

    function testManagingVanillaCurveLPTs4(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(_assets, mkUsdFraxUsdcToken, 225, mkUsdFraxUsdcBaseRewardPool);
    }

    function testManagingVanillaCurveLPTs5(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(_assets, WethYethToken, 231, wethYethBaseRewardPool);
    }

    function testManagingVanillaCurveLPTs6(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(_assets, EthEthxToken, 232, ethEthxBaseRewardPool);
    }

    function testManagingVanillaCurveLPTs7(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(_assets, CrvUsdSfraxToken, 252, crvUsdSFraxBaseRewardPool);
    }

    //============================================ Reversion Tests ===========================================

    // revert when attempt to deposit w/o having the right curve lpt for respective pid
    function testDepositWrongLPT(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);

        deal(address(USDC), address(this), _assets);
        cellar.deposit(_assets, address(this));

        // convert to coin of interest, but zero out usdc balance so cellar totalAssets doesn't deviate and revert
        ERC20 lpt = ERC20(EthFrxethToken);
        uint256 assets = priceRouter.getValue(USDC, _assets, lpt);
        deal(address(lpt), address(cellar), assets);
        deal(address(USDC), address(cellar), 0);

        uint256 pid = 128;
        (, , , address crvRewards, , ) = booster.poolInfo(pid);
        // IBaseRewardPool baseRewardPool = IBaseRewardPool(crvRewards);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(pid - 1, crvRewards, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });

        vm.expectRevert(); // TODO: actual revert statement stemming from Booster.sol likely.
        cellar.callOnAdaptor(data);
    }

    // revert when attempt to interact with not enough of the curve lpt wrt to pid
    function testDepositNotEnoughLPT(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);

        deal(address(USDC), address(this), _assets);
        cellar.deposit(_assets, address(this));

        // convert to coin of interest, but zero out usdc balance so cellar totalAssets doesn't deviate and revert
        ERC20 lpt = ERC20(EthFrxethToken);
        uint256 assets = priceRouter.getValue(USDC, _assets + 1e6, lpt);
        deal(address(lpt), address(cellar), assets);
        deal(address(USDC), address(cellar), 0);

        uint256 pid = 128;
        (, , , address crvRewards, , ) = booster.poolInfo(pid);
        // IBaseRewardPool baseRewardPool = IBaseRewardPool(crvRewards);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(pid, crvRewards, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });

        vm.expectRevert(); // TODO: actual revert statement stemming from Booster.sol likely for trying to deposit not enough lpt
        cellar.callOnAdaptor(data);
    }

    // revert ConvexAdaptor__ConvexBoosterPositionsMustBeTracked
    function testDepositUntrackedPosition(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);

        deal(address(USDC), address(this), _assets);
        cellar.deposit(_assets, address(this));

        // convert to coin of interest, but zero out usdc balance so cellar totalAssets doesn't deviate and revert
        ERC20 lpt = ERC20(EthFrxethToken);
        uint256 assets = priceRouter.getValue(USDC, _assets + 1e6, lpt);
        deal(address(lpt), address(cellar), assets);
        deal(address(USDC), address(cellar), 0);

        uint256 pid = 128;
        (, , , address crvRewards, , ) = booster.poolInfo(pid);
        IBaseRewardPool baseRewardPool = IBaseRewardPool(crvRewards);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(pid - 1, crvRewards, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(ConvexCurveAdaptor.ConvexAdaptor__ConvexBoosterPositionsMustBeTracked.selector)
            )
        ); // TODO: actual revert statement stemming from Booster.sol likely for trying to deposit not enough lpt

        cellar.callOnAdaptor(data);
    }

    /// re-entrancy tests: where curve LPT is re-entered.

    function testReentrancyProtection1(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _verifyReentrancyProtectionWorks(
            EthFrxethPool,
            EthFrxethToken,
            EthFrxethPoolPosition,
            assets,
            EthFrxethPoolPosition
        );
    }

    function testReentrancyProtection2(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _verifyReentrancyProtectionWorks(
            EthStethNgPool,
            EthStethNgToken,
            EthStethNgPoolPosition,
            assets,
            EthStethNgPoolPosition
        );
    }

    function testReentrancyProtection3(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _verifyReentrancyProtectionWorks(
            WethYethPool,
            WethYethToken,
            WethYethPoolPosition,
            assets,
            WethYethPoolPosition
        );
    }

    function testReentrancyProtection4(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _verifyReentrancyProtectionWorks(EthEthxPool, EthEthxToken, EthEthxPoolPosition, assets, EthEthxPoolPosition);
    }

    // TODO: re-entrancy tests for remaining ITB pools of interest:
    // mkUSD-FRAXbp --> mkUsdFraxUsdcPool
    // frxETH-WETH
    // FRAX-crvUSD

    //============================================ Base Functions Tests ===========================================

    // setup() to be used && then we also make the cellar in it to have the holdingPosition as convex.
    /// TODO: could expand this by making base tests for all ITB of-interest curvePools
    // testing w/ EthFrxethPool for now

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);

        // make a new cellar w/ initialDeposit of 1e18 for the lpt. TODO: confirm that all the test pools have decimals of 1e18.
        Cellar newCellar = _createCellarWithCurveLPAsAsset(
            EthFrxethPoolERC20Position,
            EthFrxethPoolPosition,
            EthFrxethToken
        ); // TODO: make erc20Position & trust it within Registry. Usually we'd have curve positions too (w/ curveAdaptor) but this test file just bypasses that since it is not in the scope of the Convex-Curve Platform development.

        // TODO: do we need to create a new cellar or can just changing holdingPosition within setup() cellar work? For now, just going with this newCellar.
        deal((EthFrxethToken), address(this), assets);
        newCellar.deposit(assets, address(this));

        // asserts, and make sure that rewardToken hasn't been claimed.
    }

    // TODO: same as within testDeposit
    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);

        Cellar newCellar = _createCellarWithCurveLPAsAsset(
            EthFrxethPoolERC20Position,
            EthFrxethPoolPosition,
            EthFrxethToken
        );

        deal((EthFrxethToken), address(this), assets);
        newCellar.deposit(assets, address(this));
        newCellar.withdraw(assets - 2, address(this), address(this));

        // asserts, and make sure that rewardToken hasn't been claimed.
    }

    // TODO: same as within testDeposit
    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);

        Cellar newCellar = _createCellarWithCurveLPAsAsset(
            EthFrxethPoolERC20Position,
            EthFrxethPoolPosition,
            EthFrxethToken
        );
        uint256 newCellarInitialAssets = newCellar.totalAssets();

        deal((EthFrxethToken), address(this), assets);
        newCellar.deposit(assets, address(this));

        assertApproxEqAbs(
            cellar.totalAssets(),
            assets + newCellarInitialAssets,
            2,
            "Total assets should equal assets deposited/staked."
        );
    }

    /// balanceOf() tests

    function testBalanceOf(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        Cellar newCellar = _createCellarWithCurveLPAsAsset(
            EthFrxethPoolERC20Position,
            EthFrxethPoolPosition,
            EthFrxethToken
        );
        uint256 newCellarInitialAssets = newCellar.totalAssets();

        deal((EthFrxethToken), address(this), assets);
        newCellar.deposit(assets, address(this));

        assertApproxEqAbs(
            cellar.balanceOf(address(this)),
            assets,
            2,
            "Total assets should equal assets deposited/staked, and not include the initialAssets (this would be accounted for via other adaptors (ERC20 or CurveAdaptor) for liquid LPTs in cellar)."
        );

        newCellar.withdraw(assets / 2, address(this), address(this));
        assertApproxEqAbs(
            cellar.balanceOf(address(this)),
            assets / 2,
            2,
            "New balanceOf should reflect withdrawn staked LPTs from Convex-Curve Platform."
        );
    }

    /// TODO: claimRewards() tests

    // - Check that we get all the CRV, CVX, 3CRV rewards we're supposed to get --> this will require testing a couple convex markets that are currently giving said rewards. **Will need to specify the block number we're starting at**

    // TODO: DELETE THIS IF 1:1 assumption is true. --> From looking over Cellar.sol, withdrawableFrom() can include staked cvxCurveLPTs. For now I am assuming that they are 1:1 w/ curveLPTs but the tests will show that or not. \* withdrawInOrder() goes through positions and ultimately calls `withdraw()` for the respective position. \_calculateTotalAssetsOrTotalAssetsWithdrawable() uses withdrawableFrom() to calculate the amount of assets there are available to withdraw from the cellar.

    /// Test Helpers

    /**
     * @notice helper function to carry out happy-path tests with convex pools of interest to ITB
     * @dev this was created to minimize amount of code within this test file
     * Here we've tested: deposit x, deposit max, withdraw x (and claim rewards), claim rewards, claim rewards over more time, claim rewards over same time with less stake, withdraw max and claim w/ longer time span fast forwarded to show more reward accrual rate.
     * TODO: stack too deep error: declare vars within global scope if using it a ton. Or make helper structs that hold data in them.
     */
    function _manageVanillaCurveLPTs(uint256 _assets, address _lpt, uint256 _pid, address _baseRewardPool) internal {
        deal(address(USDC), address(this), _assets);
        cellar.deposit(_assets, address(this));

        // convert to coin of interest, but zero out usdc balance so cellar totalAssets doesn't deviate and revert
        ERC20 lpt = ERC20(_lpt);
        uint256 assets = priceRouter.getValue(USDC, _assets, lpt);
        deal(address(lpt), address(cellar), assets);
        deal(address(USDC), address(cellar), 0);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(_baseRewardPool);

        // TODO: implement interface within ConvexCurveAdaptor to use `ITokenMinter` or other interface to access the staking capacity within `Booster.sol`

        ERC20 rewardToken = ERC20((baseRewardPool).rewardToken());
        uint256 rewardTokenBalance0 = rewardToken.balanceOf(address(cellar));

        // Strategist deposits CurveLPT into Convex-Curve Platform Pools/Markets

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(_pid, _baseRewardPool, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 stakedLPTBalance1 = baseRewardPool.balanceOf(address(cellar));
        uint256 cellarLPTBalance1 = lpt.balanceOf(address(cellar));
        uint256 rewardTokenBalance1 = rewardToken.balanceOf(address(cellar));

        // check that correct amount was deposited for cellar
        assertEq(assets, stakedLPTBalance1, "All assets must be staked in proper baseRewardPool for Convex Market");

        assertEq(0, cellarLPTBalance1, "All assets must be transferred from cellar to Convex-Curve Market");

        assertEq(initialAssets, USDC.balanceOf(address(cellar)), "Initial Cellar deposit should still be remaining.");

        assertEq(rewardTokenBalance0, rewardTokenBalance1, "No rewards should have been claimed.");

        // Pass time.
        _skip(1 days);

        adaptorCalls[0] = _createBytesDataToWithdrawAndClaimConvexCurvePlatform(
            _baseRewardPool,
            stakedLPTBalance1 / 2,
            true
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 stakedLPTBalance2 = baseRewardPool.balanceOf(address(cellar));
        uint256 cellarLPTBalance2 = lpt.balanceOf(address(cellar));
        uint256 rewardTokenBalance2 = rewardToken.balanceOf(address(cellar));

        assertApproxEqAbs(
            stakedLPTBalance2,
            stakedLPTBalance1 / 2,
            1,
            "Should have half of the OG staked LPT in gauge."
        );

        assertApproxEqAbs(
            cellarLPTBalance2,
            stakedLPTBalance1 / 2,
            1,
            "Should have withdrawn and unwrapped back to Curve LPT and transferred back to Cellar"
        );

        assertGt(
            rewardTokenBalance2,
            rewardTokenBalance1,
            "Should have claimed some more rewardToken; it will be specific to each Convex Platform Market."
        );

        uint256 rewardsTokenAccumulation1 = rewardTokenBalance2 - rewardTokenBalance1; // rewards accrued over 1 day w/ initial stake position (all assets from initial deposit).

        // at this point we've withdrawn half, should have rewards. Now we deposit and stake more to ensure that it handles this correctly.

        uint256 additionalDeposit = cellarLPTBalance2 / 2;
        uint256 expectedNewStakedBalance = additionalDeposit + stakedLPTBalance2;

        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(_pid, _baseRewardPool, additionalDeposit);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 stakedLPTBalance3 = baseRewardPool.balanceOf(address(cellar));
        uint256 cellarLPTBalance3 = lpt.balanceOf(address(cellar));
        uint256 rewardTokenBalance3 = rewardToken.balanceOf(address(cellar));

        assertApproxEqAbs(
            stakedLPTBalance3,
            expectedNewStakedBalance,
            1,
            "Should have half of the OG staked LPT PLUS the new additional deposit in gauge."
        );

        assertApproxEqAbs(
            cellarLPTBalance3,
            stakedLPTBalance2 / 2,
            1,
            "Should have half of cellarLPTBalance2 in the Cellar"
        );

        assertEq(
            rewardTokenBalance3,
            rewardTokenBalance2,
            "should have the same amount of rewards as before since deposits do not claim rewards in same tx"
        );

        // test claiming without any time past to show that rewards should not be accruing / no transferrance should occur to cellar.

        adaptorCalls[0] = _createBytesDataToGetRewardsConvexCurvePlatform(_pid, _baseRewardPool, true);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 rewardTokenBalance4 = rewardToken.balanceOf(address(cellar));

        assertEq(rewardTokenBalance4, rewardTokenBalance3, "No time passed since last reward claim");

        _skip(1 days);

        // claim rewards and show that reward accrual is actually getting lesser due to lesser amount deposited/staked
        cellar.callOnAdaptor(data); // repeat last getReward call

        uint256 rewardTokenBalance5 = rewardToken.balanceOf(address(cellar));
        uint256 rewardsTokenAccumulation2 = rewardTokenBalance5 - rewardTokenBalance4; // rewards accrued over 1 day w/ less than initial stake position.

        assertGt(rewardTokenBalance5, rewardTokenBalance4, "Should have claimed some more rewardToken.");
        assertLt(
            rewardsTokenAccumulation2,
            rewardsTokenAccumulation1,
            "rewards accrued over 1 day w/ less than initial stake position should result in less reward accumulation."
        );

        // check type(uint256).max works for deposit
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(_pid, _baseRewardPool, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // thus at this point, all LPT is now deposited and staked from the cellar.
        uint256 stakedLPTBalance4 = baseRewardPool.balanceOf(address(cellar));
        uint256 cellarLPTBalance4 = lpt.balanceOf(address(cellar));
        uint256 rewardTokenBalance6 = rewardToken.balanceOf(address(cellar));

        assertEq(stakedLPTBalance4, assets, "All lpt should be staked now again.");

        assertEq(cellarLPTBalance4, 0, "No lpt should be in cellar again.");

        assertEq(rewardTokenBalance6, rewardTokenBalance5, "No changes to rewards should have occurred.");

        // Now we have the initialAssets amount of LPT in again, we can test that after MORE time with the same mount, more rewards are accrued.
        _skip(10 days);

        adaptorCalls[0] = _createBytesDataToGetRewardsConvexCurvePlatform(_pid, _baseRewardPool, true);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data); // repeat last getReward call

        uint256 rewardTokenBalance7 = rewardToken.balanceOf(address(cellar));
        uint256 rewardsTokenAccumulation3 = rewardTokenBalance7 - rewardTokenBalance6; // rewards accrued over 1 day w/ less than initial stake position.

        assertGt(rewardTokenBalance6, rewardTokenBalance6, "Should have claimed some more rewardToken.");
        assertGt(
            rewardsTokenAccumulation3,
            rewardsTokenAccumulation1,
            "rewards accrued over 10 days should be more than initial award accrual over 1 day."
        );

        // TODO: do we want to test for the actual rate that we should be getting rewardTokens, or is the fact that the amounts are getting bigger and bigger when time and/or stakeAmount increases enough?

        // withdraw and unwrap portion immediately
        _skip(11 days);

        adaptorCalls[0] = _createBytesDataToWithdrawAndClaimConvexCurvePlatform(
            _baseRewardPool,
            type(uint256).max,
            true
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 stakedLPTBalance5 = baseRewardPool.balanceOf(address(cellar));
        uint256 cellarLPTBalance5 = lpt.balanceOf(address(cellar));
        uint256 rewardTokenBalance8 = rewardToken.balanceOf(address(cellar));
        uint256 rewardsTokenAccumulation4 = rewardTokenBalance8 - rewardTokenBalance7; // rewards accrued over 11 days w/ full assets amount of lpt staked

        assertEq(stakedLPTBalance5, 0, "All staked lpt should have been unwrapped and withdrawn to cellar");
        assertGt(assets, cellarLPTBalance5, "Cellar should have all lpt now");
        assertGt(rewardTokenBalance8, rewardTokenBalance7, "Cellar Reward Balance should have increased.");
        assertGt(
            rewardsTokenAccumulation4,
            rewardsTokenAccumulation3,
            "Cellar Reward accrual rate should have been more because it accrued over 11 days vs 10 days."
        );
    }

    /// TODO: test to check extra rewards --> need to test only on convex markets that have extra rewards associated to it.

    /// TODO: test reward attainment within withdraw and getReward() where extra_reward bool is false, and then true.

    /// Generic Helpers

    function _add2PoolAssetToPriceRouter(
        address pool,
        address token,
        bool isCorrelated,
        uint256 expectedPrice,
        ERC20 underlyingOrConstituent0,
        ERC20 underlyingOrConstituent1,
        bool divideRate0,
        bool divideRate1
    ) internal {
        Curve2PoolExtension.ExtensionStorage memory stor;
        stor.pool = pool;
        stor.isCorrelated = isCorrelated;
        stor.underlyingOrConstituent0 = address(underlyingOrConstituent0);
        stor.underlyingOrConstituent1 = address(underlyingOrConstituent1);
        stor.divideRate0 = divideRate0;
        stor.divideRate1 = divideRate1;
        PriceRouter.AssetSettings memory settings;
        settings.derivative = EXTENSION_DERIVATIVE;
        settings.source = address(curve2PoolExtension);

        priceRouter.addAsset(ERC20(token), settings, abi.encode(stor), expectedPrice);
    }

    function _skip(uint256 time) internal {
        uint256 blocksToRoll = time / 12; // Assumes an avg 12 second block time.
        skip(time);
        vm.roll(block.number + blocksToRoll);
        mockWETHdataFeed.setMockUpdatedAt(block.timestamp);
        mockUSDCdataFeed.setMockUpdatedAt(block.timestamp);
        mockDAI_dataFeed.setMockUpdatedAt(block.timestamp);
        mockUSDTdataFeed.setMockUpdatedAt(block.timestamp);
        mockFRAXdataFeed.setMockUpdatedAt(block.timestamp);
        mockSTETHdataFeed.setMockUpdatedAt(block.timestamp);
        mockRETHdataFeed.setMockUpdatedAt(block.timestamp);
    }

    function _setupCellarWithConvexDeposit(
        uint256 _assets,
        address _lpt,
        uint256 _pid,
        address _baseRewardPool
    ) internal {
        deal(address(USDC), address(this), _assets);
        cellar.deposit(_assets, address(this));

        // convert to coin of interest, but zero out usdc balance so cellar totalAssets doesn't deviate and revert
        ERC20 lpt = ERC20(_lpt);
        uint256 assets = priceRouter.getValue(USDC, _assets, lpt);
        deal(address(lpt), address(cellar), assets);
        deal(address(USDC), address(cellar), 0);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(_baseRewardPool);

        // TODO: implement interface within ConvexCurveAdaptor to use `ITokenMinter` or other interface to access the staking capacity within `Booster.sol`

        ERC20 rewardToken = ERC20((baseRewardPool).rewardToken());
        uint256 rewardTokenBalance0 = rewardToken.balanceOf(address(cellar));

        // Strategist deposits CurveLPT into Convex-Curve Platform Pools/Markets

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(_pid, _baseRewardPool, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _verifyReentrancyProtectionWorks(
        address poolAddress,
        address lpToken,
        uint32 position,
        uint256 assets,
        uint32 convexPosition
    ) internal {
        // Create a cellar that uses the curve token as the asset.
        cellar = _createCellarWithCurveLPAsAsset(position, convexPosition, lpToken);

        deal(lpToken, address(this), assets);
        ERC20(lpToken).safeApprove(address(cellar), assets);

        CurvePool pool = CurvePool(poolAddress);
        bytes32 slot0 = bytes32(uint256(0));

        // Get the original slot value;
        bytes32 originalValue = vm.load(address(pool), slot0);

        // Set lock slot to 2 to lock it. Then try to deposit while pool is "re-entered".
        vm.store(address(pool), slot0, bytes32(uint256(2)));
        vm.expectRevert();
        cellar.deposit(assets, address(this)); // holdingPosition is convex staking, but make sure it reverts when re-entrancy toggle is on. Rest of the test does similar checks.

        // Change lock back to unlocked state
        vm.store(address(pool), slot0, originalValue);

        // Deposit should work now.
        cellar.deposit(assets, address(this));

        // Set lock slot to 2 to lock it. Then try to withdraw while pool is "re-entered".
        vm.store(address(pool), slot0, bytes32(uint256(2)));
        vm.expectRevert();
        cellar.withdraw(assets / 2, address(this), address(this));

        // Change lock back to unlocked state
        vm.store(address(pool), slot0, originalValue);

        // Withdraw should work now.
        cellar.withdraw(assets / 2, address(this), address(this));
    }

    /**
     * @notice Creates cellar w/ Curve LPT as baseAsset, and holdingPosition as ConvexCurveAdaptor Position.
     */
    function _createCellarWithCurveLPAsAsset(
        uint32 position,
        uint32 convexPosition,
        address lpToken
    ) internal returns (Cellar newCellar) {
        string memory cellarName = "Test Convex Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        ERC20 erc20LpToken = ERC20(lpToken);

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(lpToken, address(this), initialDeposit);
        erc20LpToken.approve(cellarAddress, initialDeposit);

        bytes memory creationCode = type(MockCellarWithOracle).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(this),
            registry,
            erc20LpToken,
            cellarName,
            cellarName,
            position,
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );
        newCellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        newCellar.addAdaptorToCatalogue(address(convexCurveAdaptor));
        newCellar.addPositionToCatalogue(convexPosition);
        newCellar.addPosition(0, convexPosition, abi.encode(true), false);
        newCellar.setHoldingPosition(convexPosition);
    }
}
