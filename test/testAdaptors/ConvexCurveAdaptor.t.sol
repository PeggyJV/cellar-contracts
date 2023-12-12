// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { ConvexCurveAdaptor } from "src/modules/adaptors/Convex/ConvexCurveAdaptor.sol";
import { IBaseRewardPool } from "src/interfaces/external/Convex/IBaseRewardPool.sol";
import { IBooster } from "src/interfaces/external/Convex/IBooster.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { console } from "@forge-std/Test.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { CurveEMAExtension } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";
import { Curve2PoolExtension } from "src/modules/price-router/Extensions/Curve/Curve2PoolExtension.sol";
import { CurvePool } from "src/interfaces/external/Curve/CurvePool.sol";
import { MockCellarWithOracle } from "src/mocks/MockCellarWithOracle.sol";

/**
 * @title ConvexCurveAdaptorTest
 * @author crispymangoes, 0xEinCodes
 * @notice Cellar Adaptor tests with Convex-Curve markets
 * LPT4, LPT5, LPT7 are the ones that we exclude from reward assert tests because they have reward streaming paused at the test blockNumber / currently
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

    uint256 public cvxBalance0;
    uint256 public cvxBalance1;
    uint256 public cvxBalance2;
    uint256 public cvxBalance3;
    uint256 public cvxBalance4;
    uint256 public cvxBalance5;
    uint256 public cvxBalance6;
    uint256 public cvxBalance7;
    uint256 public cvxBalance8;

    uint256 public cvxRewardAccumulationRate1;
    uint256 public cvxRewardAccumulationRate2;
    uint256 public cvxRewardAccumulationRate3;
    uint256 public cvxRewardAccumulationRate4;

    uint256 public stakedLPTBalance1;
    uint256 public cellarLPTBalance1;
    uint256 public rewardTokenBalance1;
    uint256 public stakedLPTBalance2;
    uint256 public cellarLPTBalance2;
    uint256 public rewardTokenBalance2;
    uint256 public additionalDeposit;
    uint256 public expectedNewStakedBalance;
    uint256 public stakedLPTBalance3;
    uint256 public cellarLPTBalance3;
    uint256 public rewardTokenBalance3;
    uint256 public rewardTokenBalance4;
    uint256 public rewardTokenBalance5;
    uint256 public rewardsTokenAccumulation2;
    uint256 public stakedLPTBalance4;
    uint256 public cellarLPTBalance4;
    uint256 public rewardTokenBalance6;
    uint256 public rewardTokenBalance7;
    uint256 public rewardsTokenAccumulation3;
    uint256 public stakedLPTBalance5;
    uint256 public cellarLPTBalance5;
    uint256 public rewardTokenBalance8;
    uint256 public rewardsTokenAccumulation4;

    bytes4 public curveWithdrawAdminFeesSelector = CurvePool.withdraw_admin_fees.selector;
    /// stack too deep global vars

    ConvexCurveAdaptor private convexCurveAdaptor;
    IBooster public immutable booster = IBooster(convexCurveMainnetBooster);
    IBaseRewardPool public rewardsPool; // varies per convex market

    WstEthExtension private wstethExtension;
    CurveEMAExtension private curveEMAExtension;
    Curve2PoolExtension private curve2PoolExtension;

    MockDataFeed public mockWETHdataFeed;
    MockDataFeed public mockCVXdataFeed;
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

    // ConvexCurveAdaptor Positions
    uint32 private EthFrxethPoolPosition = 11; // https://www.convexfinance.com/stake/ethereum/128
    uint32 private EthStethNgPoolPosition = 12;
    uint32 private fraxCrvUsdPoolPosition = 13;
    uint32 private mkUsdFraxUsdcPoolPosition = 14;
    uint32 private WethYethPoolPosition = 15;
    uint32 private EthEthxPoolPosition = 16;

    // erc20 positions for Curve LPTs
    uint32 private EthFrxethERC20Position = 17;
    uint32 private EthStethNgERC20Position = 18;
    uint32 private fraxCrvUsdERC20Position = 19;
    uint32 private mkUsdFraxUsdcERC20Position = 20;
    uint32 private WethYethERC20Position = 21;
    uint32 private EthEthxERC20Position = 22;
    uint32 private CrvUsdSfraxERC20Position = 23;
    // uint32 private sFraxPosition = 24;
    uint32 private CrvUsdSfraxPoolPosition = 24;

    uint32 private slippage = 0.9e4;
    uint256 public initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18643715;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockWETHdataFeed = new MockDataFeed(WETH_USD_FEED);
        mockCVXdataFeed = new MockDataFeed(CVX_USD_FEED);
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

        // Add CVX pricing.
        price = uint256(IChainlinkAggregator(CVX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockCVXdataFeed));
        priceRouter.addAsset(CVX, settings, abi.encode(stor), price);

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
        cStor.lowerBound = 0;
        cStor.upperBound = 10e4;
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
        cStor.lowerBound = 0;
        cStor.upperBound = 10e4;
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
        cStor.lowerBound = 0;
        cStor.upperBound = 10e4;
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
        cStor.lowerBound = 0;
        cStor.upperBound = 10e4;
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
        cStor.lowerBound = 0;
        cStor.upperBound = 10e4;
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
        cStor.lowerBound = 0;
        cStor.upperBound = 10e4;
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

        _add2PoolAssetToPriceRouter(FraxUsdcPool, FraxUsdcToken, true, 1e8, FRAX, USDC, false, false, 0, 10e4);

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
            false,
            0,
            10e4
        );

        // EthStethNgPool
        // EthStethNgToken
        // EthStethNgGauge
        _add2PoolAssetToPriceRouter(EthStethNgPool, EthStethNgToken, true, 2_100e8, WETH, STETH, false, false, 0, 10e4);

        // WethYethPool
        // WethYethToken
        // WethYethGauge
        _add2PoolAssetToPriceRouter(WethYethPool, WethYethToken, true, 2_100e8, WETH, YETH, false, false, 0, 10e4);
        // EthEthxPool
        // EthEthxToken
        // EthEthxGauge
        _add2PoolAssetToPriceRouter(EthEthxPool, EthEthxToken, true, 2_100e8, WETH, ETHX, false, true, 0, 10e4);

        // CrvUsdSfraxPool
        // CrvUsdSfraxToken
        // CrvUsdSfraxGauge
        _add2PoolAssetToPriceRouter(CrvUsdSfraxPool, CrvUsdSfraxToken, true, 1e8, CRVUSD, FRAX, false, false, 0, 10e4);

        // Likely going to be in the frax platform adaptor tests but will test here in case we need to go into the convex-curve platform tests

        // frxETH-WETH
        // FRAX-crvUSD
        // frxETH-ETH

        // WethFrxethPool
        // WethFrxethToken
        // WethFrxethGauge
        _add2PoolAssetToPriceRouter(WethFrxethPool, WethFrxethToken, true, 2100e8, WETH, FRXETH, false, false, 0, 10e4);
        // EthFrxethPool
        // EthFrxethToken
        // EthFrxethGauge
        _add2PoolAssetToPriceRouter(EthFrxethPool, EthFrxethToken, true, 2100e8, WETH, FRXETH, false, false, 0, 10e4);
        // FraxCrvUsdPool
        // FraxCrvUsdToken
        // FraxCrvUsdGauge
        _add2PoolAssetToPriceRouter(FraxCrvUsdPool, FraxCrvUsdToken, true, 1e8, FRAX, CRVUSD, false, false, 0, 10e4);

        convexCurveAdaptor = new ConvexCurveAdaptor(convexCurveMainnetBooster, address(WETH));

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
            abi.encode(
                128,
                ethFrxethBaseRewardPool,
                EthFrxethToken,
                EthFrxethPool,
                bytes4(keccak256(abi.encodePacked("price_oracle()")))
            )
        );
        registry.trustPosition(
            EthStethNgPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(
                177,
                ethStethNgBaseRewardPool,
                EthStethNgToken,
                CurvePool(EthStethNgPool),
                CurvePool.withdraw_admin_fees.selector
            )
        );
        registry.trustPosition(
            fraxCrvUsdPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(
                187,
                fraxCrvUsdBaseRewardPool,
                FraxCrvUsdToken,
                CurvePool(FraxCrvUsdPool),
                CurvePool.withdraw_admin_fees.selector
            )
        );
        registry.trustPosition(
            mkUsdFraxUsdcPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(
                225,
                mkUsdFraxUsdcBaseRewardPool,
                mkUsdFraxUsdcToken,
                CurvePool(mkUsdFraxUsdcPool),
                CurvePool.withdraw_admin_fees.selector
            )
        );
        registry.trustPosition(
            WethYethPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(
                231,
                wethYethBaseRewardPool,
                WethYethToken,
                CurvePool(WethYethPool),
                CurvePool.withdraw_admin_fees.selector
            )
        );
        registry.trustPosition(
            EthEthxPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(
                232,
                ethEthxBaseRewardPool,
                EthEthxToken,
                CurvePool(EthEthxPool),
                CurvePool.withdraw_admin_fees.selector
            )
        );

        registry.trustPosition(
            CrvUsdSfraxPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(
                252,
                crvUsdSFraxBaseRewardPool,
                CrvUsdSfraxToken,
                CurvePool(CrvUsdSfraxPool),
                CurvePool.withdraw_admin_fees.selector
            )
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

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(cellarAddress, initialDeposit);

        bytes memory creationCode = type(MockCellarWithOracle).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            usdcPosition,
            abi.encode(0),
            initialDeposit,
            platformCut,
            type(uint192).max
        );
        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        USDC.safeApprove(address(cellar), type(uint256).max);

        for (uint32 i = 2; i < 25; ++i) cellar.addPositionToCatalogue(i);
        for (uint32 i = 2; i < 25; ++i) cellar.addPosition(0, i, abi.encode(true), false);

        cellar.setRebalanceDeviation(0.01e18);

        cellar.addAdaptorToCatalogue(address(convexCurveAdaptor));

        initialAssets = cellar.totalAssets();
    }

    //============================================ Happy Path Tests ===========================================

    function testManagingVanillaCurveLPTs1(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(
            _assets,
            EthFrxethToken,
            128,
            ethFrxethBaseRewardPool,
            EthFrxethPool,
            bytes4(keccak256(abi.encodePacked("price_oracle()")))
        );
    }

    function testManagingVanillaCurveLPTs2(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(
            _assets,
            EthStethNgToken,
            177,
            ethStethNgBaseRewardPool,
            EthStethNgPool,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingVanillaCurveLPTs3(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(
            _assets,
            FraxCrvUsdToken,
            187,
            fraxCrvUsdBaseRewardPool,
            FraxCrvUsdPool,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingVanillaCurveLPTs4(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(
            _assets,
            mkUsdFraxUsdcToken,
            225,
            mkUsdFraxUsdcBaseRewardPool,
            mkUsdFraxUsdcPool,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingVanillaCurveLPTs5(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(
            _assets,
            WethYethToken,
            231,
            wethYethBaseRewardPool,
            WethYethPool,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingVanillaCurveLPTs6(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(
            _assets,
            EthEthxToken,
            232,
            ethEthxBaseRewardPool,
            EthEthxPool,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingVanillaCurveLPTs7(uint256 _assets) external {
        _assets = bound(_assets, 1e6, 100_000e6);
        _manageVanillaCurveLPTs(
            _assets,
            CrvUsdSfraxToken,
            252,
            crvUsdSFraxBaseRewardPool,
            CrvUsdSfraxPool,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    // //============================================ Reversion Tests ===========================================

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
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(
            pid - 1,
            crvRewards,
            ERC20(EthFrxethToken),
            CurvePool(EthFrxethPool),
            curveWithdrawAdminFeesSelector,
            assets
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ConvexCurveAdaptor.ConvexAdaptor__ConvexBoosterPositionsMustBeTracked.selector,
                    pid - 1,
                    crvRewards,
                    ERC20(EthFrxethToken),
                    CurvePool(EthFrxethPool),
                    curveWithdrawAdminFeesSelector
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // revert when attempt to interact with not enough of the curve lpt wrt to pid
    function testDepositNotEnoughLPT(uint256 _assets) external {
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
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(
            pid,
            crvRewards,
            ERC20(EthFrxethToken),
            CurvePool(EthFrxethPool),
            curveWithdrawAdminFeesSelector,
            assets + 1e18
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ConvexCurveAdaptor.ConvexAdaptor__ConvexBoosterPositionsMustBeTracked.selector,
                    pid,
                    crvRewards,
                    ERC20(EthFrxethToken),
                    CurvePool(EthFrxethPool),
                    curveWithdrawAdminFeesSelector
                )
            )
        );
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

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(
            pid - 1,
            crvRewards,
            ERC20(EthFrxethToken),
            CurvePool(EthFrxethPool),
            curveWithdrawAdminFeesSelector,
            assets
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    ConvexCurveAdaptor.ConvexAdaptor__ConvexBoosterPositionsMustBeTracked.selector,
                    pid - 1,
                    crvRewards,
                    ERC20(EthFrxethToken),
                    CurvePool(EthFrxethPool),
                    curveWithdrawAdminFeesSelector
                )
            )
        );

        cellar.callOnAdaptor(data);
    }

    // re-entrancy tests: where curve LPT is re-entered.
    function testReentrancyProtection1(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _verifyReentrancyProtectionWorks(
            EthFrxethPool,
            EthFrxethToken,
            EthFrxethERC20Position,
            assets,
            EthFrxethPoolPosition
        );
    }

    function testReentrancyProtection2(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _verifyReentrancyProtectionWorks(
            EthStethNgPool,
            EthStethNgToken,
            EthStethNgERC20Position,
            assets,
            EthStethNgPoolPosition
        );
    }

    function testReentrancyProtection3(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _verifyReentrancyProtectionWorks(
            WethYethPool,
            WethYethToken,
            WethYethERC20Position,
            assets,
            WethYethPoolPosition
        );
    }

    function testReentrancyProtection4(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _verifyReentrancyProtectionWorks(EthEthxPool, EthEthxToken, EthEthxERC20Position, assets, EthEthxPoolPosition);
    }

    // //============================================ Base Functions Tests ===========================================

    // In practice, usually cellars would have curve positions too (w/ curveAdaptor) but this test file just bypasses that since it is not in the scope of the Convex-Curve Platform development. You'll notice that in the `_createCellarWithCurveLPAsAsset()` helper paired w/ `setup()`
    // testing w/ EthFrxethPool for now

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);

        Cellar newCellar = _createCellarWithCurveLPAsAsset(
            EthFrxethERC20Position,
            EthFrxethPoolPosition,
            EthFrxethToken
        );

        ERC20 EthFrxethTokenERC20 = ERC20(EthFrxethToken);

        deal((EthFrxethToken), address(this), assets);
        EthFrxethTokenERC20.safeApprove(address(newCellar), assets);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(ethFrxethBaseRewardPool);
        ERC20 rewardToken = ERC20((baseRewardPool).rewardToken());
        uint256 rewardTokenBalance0 = rewardToken.balanceOf(address(newCellar));

        uint256 oldAssets = EthFrxethTokenERC20.balanceOf(address(newCellar));

        uint256 userBalance1 = EthFrxethTokenERC20.balanceOf(address(this));
        assertEq(userBalance1, assets, "Starting amount of CurveLPT in test contract should be `assets`.");

        newCellar.deposit(assets, address(this));

        uint256 userBalance2 = EthFrxethTokenERC20.balanceOf(address(this));
        stakedLPTBalance1 = baseRewardPool.balanceOf(address(newCellar)); // not an erc20 balanceOf()
        cellarLPTBalance1 = EthFrxethTokenERC20.balanceOf(address(newCellar));
        rewardTokenBalance1 = rewardToken.balanceOf(address(newCellar));

        assertEq(userBalance2, 0, "All CurveLPT transferred from test contract to newCellar.");
        // check that correct amount was deposited for cellar
        assertEq(assets, stakedLPTBalance1, "All assets must be staked in proper baseRewardPool for Convex Market");
        assertEq(
            oldAssets,
            cellarLPTBalance1,
            "All assets must be transferred from newCellar to Convex-Curve Market except oldAssets upon cellar creation."
        );
        assertEq(rewardTokenBalance0, rewardTokenBalance1, "No rewards should have been claimed.");
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);

        Cellar newCellar = _createCellarWithCurveLPAsAsset(
            EthFrxethERC20Position,
            EthFrxethPoolPosition,
            EthFrxethToken
        );

        ERC20 EthFrxethTokenERC20 = ERC20(EthFrxethToken);

        deal((EthFrxethToken), address(this), assets);
        EthFrxethTokenERC20.safeApprove(address(newCellar), assets);

        uint256 userBalance1 = EthFrxethTokenERC20.balanceOf(address(this));

        newCellar.deposit(assets, address(this));
        newCellar.withdraw(assets, address(this), address(this));

        uint256 userBalance2 = EthFrxethTokenERC20.balanceOf(address(this));
        assertEq(
            userBalance2,
            userBalance1,
            "All assets should be withdrawn from the cellar position back to the test contract"
        );
        // asserts, and make sure that rewardToken hasn't been claimed.
    }

    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);

        Cellar newCellar = _createCellarWithCurveLPAsAsset(
            EthFrxethERC20Position,
            EthFrxethPoolPosition,
            EthFrxethToken
        );
        uint256 newCellarInitialAssets = newCellar.totalAssets();

        deal((EthFrxethToken), address(this), assets);
        ERC20(EthFrxethToken).safeApprove(address(newCellar), assets);

        newCellar.deposit(assets, address(this));

        assertApproxEqAbs(
            newCellar.totalAssets(),
            assets + newCellarInitialAssets,
            2,
            "Total assets should equal assets deposited/staked."
        );
    }

    /// balanceOf() tests

    function testBalanceOf(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        Cellar newCellar = _createCellarWithCurveLPAsAsset(
            EthFrxethERC20Position,
            EthFrxethPoolPosition,
            EthFrxethToken
        );

        deal((EthFrxethToken), address(this), assets);
        ERC20(EthFrxethToken).safeApprove(address(newCellar), assets);

        newCellar.deposit(assets, address(this)); // should deposit, and stake into conve because it is holdingPosition.

        assertApproxEqAbs(
            newCellar.balanceOf(address(this)),
            assets,
            2,
            "Total assets should equal assets deposited/staked, and not include the initialAssets (this would be accounted for via other adaptors (ERC20 or CurveAdaptor) for liquid LPTs in cellar)."
        );

        newCellar.withdraw(assets / 2, address(this), address(this));
        assertApproxEqAbs(
            newCellar.balanceOf(address(this)),
            assets / 2,
            2,
            "New balanceOf should reflect withdrawn staked LPTs from Convex-Curve Platform."
        );
    }

    /// Test Helpers

    /**
     * @notice helper function to carry out happy-path tests with convex pools of interest to ITB
     * @dev this was created to minimize amount of code within this test file
     * Here we've tested: deposit x, deposit max, withdraw x (and claim rewards), claim rewards, claim rewards over more time, claim rewards over same time with less stake, withdraw max and claim w/ longer time span fast forwarded to show more reward accrual rate.
     */
    function _manageVanillaCurveLPTs(
        uint256 _assets,
        address _lpt,
        uint256 _pid,
        address _baseRewardPool,
        address _curvePool,
        bytes4 selector
    ) internal {
        deal(address(USDC), address(this), _assets);
        cellar.deposit(_assets, address(this));

        // convert to coin of interest, but zero out usdc balance so cellar totalAssets doesn't deviate and revert
        ERC20 lpt = ERC20(_lpt);
        CurvePool curvePool = CurvePool(_curvePool);
        uint256 assets = priceRouter.getValue(USDC, _assets, lpt);
        deal(address(lpt), address(cellar), assets);
        deal(address(USDC), address(cellar), 0);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(_baseRewardPool);

        ERC20 rewardToken = ERC20((baseRewardPool).rewardToken());
        uint256 rewardTokenBalance0 = rewardToken.balanceOf(address(cellar));
        cvxBalance0 = CVX.balanceOf(address(cellar));

        // Strategist deposits CurveLPT into Convex-Curve Platform Pools/Markets

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(
            _pid,
            _baseRewardPool,
            lpt,
            curvePool,
            selector,
            assets
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        stakedLPTBalance1 = baseRewardPool.balanceOf(address(cellar));
        cellarLPTBalance1 = lpt.balanceOf(address(cellar));
        rewardTokenBalance1 = rewardToken.balanceOf(address(cellar));
        cvxBalance1 = CVX.balanceOf(address(cellar));

        // check that correct amount was deposited for cellar
        assertEq(assets, stakedLPTBalance1, "All assets must be staked in proper baseRewardPool for Convex Market");

        assertEq(0, cellarLPTBalance1, "All assets must be transferred from cellar to Convex-Curve Market");

        assertEq(rewardTokenBalance0, rewardTokenBalance1, "No rewards should have been claimed.");
        assertEq(cvxBalance0, cvxBalance1, "No CVX rewards should have been claimed.");

        // Pass time.
        _skip(1 days);

        adaptorCalls[0] = _createBytesDataToWithdrawAndClaimConvexCurvePlatform(
            _baseRewardPool,
            stakedLPTBalance1 / 2,
            true
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        stakedLPTBalance2 = baseRewardPool.balanceOf(address(cellar));
        cellarLPTBalance2 = lpt.balanceOf(address(cellar));
        rewardTokenBalance2 = rewardToken.balanceOf(address(cellar));
        cvxBalance2 = CVX.balanceOf(address(cellar));

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

        // NOTE: certain _pids correspond to Convex-Curve markets that have their reward streaming paused and thus will have their rewards-associated tests ignored in our test suite (at the time of the blockNumber for these tests)
        if (_pid != 231) {
            assertGt(
                rewardTokenBalance2,
                rewardTokenBalance1,
                "Should have claimed some more rewardToken; it will be specific to each Convex Platform Market."
            );
            assertGt(cvxBalance2, cvxBalance1, "Should have claimed some CVX");
        }

        uint256 rewardsTokenAccumulation1 = rewardTokenBalance2 - rewardTokenBalance1; // rewards accrued over 1 day w/ initial stake position (all assets from initial deposit).
        cvxRewardAccumulationRate1 = cvxBalance2 - cvxBalance1;

        // at this point we've withdrawn half, should have rewards. Now we deposit and stake more to ensure that it handles this correctly.

        additionalDeposit = cellarLPTBalance2 / 2;
        expectedNewStakedBalance = additionalDeposit + stakedLPTBalance2;

        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(
            _pid,
            _baseRewardPool,
            lpt,
            curvePool,
            selector,
            additionalDeposit
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        stakedLPTBalance3 = baseRewardPool.balanceOf(address(cellar));
        cellarLPTBalance3 = lpt.balanceOf(address(cellar));
        rewardTokenBalance3 = rewardToken.balanceOf(address(cellar));
        cvxBalance3 = CVX.balanceOf(address(cellar));
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

        assertEq(
            cvxBalance3,
            cvxBalance2,
            "should have the same amount of CVX rewards as before since deposits do not claim rewards in same tx"
        );

        // test claiming without any time past to show that rewards should not be accruing / no transferrance should occur to cellar.

        adaptorCalls[0] = _createBytesDataToGetRewardsConvexCurvePlatform(_baseRewardPool, true);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        rewardTokenBalance4 = rewardToken.balanceOf(address(cellar));
        cvxBalance4 = CVX.balanceOf(address(cellar));

        assertEq(rewardTokenBalance4, rewardTokenBalance3, "No time passed since last reward claim");

        assertEq(cvxBalance4, cvxBalance3, "No time passed since last CVX claim");

        _skip(1 days);

        // claim rewards and show that reward accrual is actually getting lesser due to lesser amount deposited/staked
        adaptorCalls[0] = _createBytesDataToGetRewardsConvexCurvePlatform(_baseRewardPool, true);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data); // repeat last getReward call

        rewardTokenBalance5 = rewardToken.balanceOf(address(cellar));
        cvxBalance5 = CVX.balanceOf(address(cellar));
        rewardsTokenAccumulation2 = rewardTokenBalance5 - rewardTokenBalance4; // rewards accrued over 1 day w/ less than initial stake position.
        cvxRewardAccumulationRate2 = cvxBalance5 - cvxBalance4;

        if (_pid != 225 && _pid != 231 && _pid != 252) {
            assertGt(rewardTokenBalance5, rewardTokenBalance4, "CHECK 1: Should have claimed some more rewardToken.");
            assertLt(
                rewardsTokenAccumulation2,
                rewardsTokenAccumulation1,
                "rewards accrued over 1 day w/ less than initial stake position should result in less reward accumulation."
            );

            assertGt(cvxBalance5, cvxBalance4, "CHECK 1: Should have claimed some more CVX.");
            assertLt(
                cvxRewardAccumulationRate2,
                cvxRewardAccumulationRate1,
                "CVX rewards accrued over 1 day w/ less than initial stake position should result in less reward accumulation."
            );
        }

        // check type(uint256).max works for deposit
        adaptorCalls[0] = _createBytesDataToDepositToConvexCurvePlatform(
            _pid,
            _baseRewardPool,
            lpt,
            curvePool,
            selector,
            type(uint256).max
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // thus at this point, all LPT is now deposited and staked from the cellar.
        stakedLPTBalance4 = baseRewardPool.balanceOf(address(cellar));
        cellarLPTBalance4 = lpt.balanceOf(address(cellar));
        rewardTokenBalance6 = rewardToken.balanceOf(address(cellar));
        cvxBalance6 = CVX.balanceOf(address(cellar));

        assertEq(stakedLPTBalance4, assets, "All lpt should be staked now again.");

        assertEq(cellarLPTBalance4, 0, "No lpt should be in cellar again.");

        assertEq(rewardTokenBalance6, rewardTokenBalance5, "No changes to rewards should have occurred.");
        assertEq(cvxBalance6, cvxBalance5, "No changes to CVX rewards should have occurred.");

        // Now we have the initialAssets amount of LPT in again, we can test that after MORE time with the same mount, more rewards are accrued.
        _skip(10 days);

        adaptorCalls[0] = _createBytesDataToGetRewardsConvexCurvePlatform(_baseRewardPool, true);
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data); // repeat last getReward call

        rewardTokenBalance7 = rewardToken.balanceOf(address(cellar));
        rewardsTokenAccumulation3 = rewardTokenBalance7 - rewardTokenBalance6; // rewards accrued over 1 day w/ less than initial stake position.
        cvxBalance7 = CVX.balanceOf(address(cellar));
        cvxRewardAccumulationRate3 = cvxBalance7 - cvxBalance6;
        if (_pid != 225 && _pid != 231 && _pid != 252) {
            assertGt(rewardTokenBalance7, rewardTokenBalance6, "CHECK 2: Should have claimed some more rewardToken.");

            assertGt(
                rewardsTokenAccumulation3,
                rewardsTokenAccumulation1,
                "rewards accrued over 10 days should be more than initial award accrual over 1 day."
            );
            assertGt(
                cvxRewardAccumulationRate3,
                cvxRewardAccumulationRate1,
                "rewards accrued over 10 days should be more than initial award accrual over 1 day."
            );
        }

        // withdraw and unwrap portion immediately
        _skip(11 days);

        adaptorCalls[0] = _createBytesDataToWithdrawAndClaimConvexCurvePlatform(
            _baseRewardPool,
            type(uint256).max,
            true
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(convexCurveAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        stakedLPTBalance5 = baseRewardPool.balanceOf(address(cellar));
        cellarLPTBalance5 = lpt.balanceOf(address(cellar));
        rewardTokenBalance8 = rewardToken.balanceOf(address(cellar));
        rewardsTokenAccumulation4 = rewardTokenBalance8 - rewardTokenBalance7; // rewards accrued over 11 days w/ full assets amount of lpt staked
        cvxBalance8 = CVX.balanceOf(address(cellar));
        cvxRewardAccumulationRate4 = cvxBalance8 - cvxBalance7;

        assertEq(stakedLPTBalance5, 0, "All staked lpt should have been unwrapped and withdrawn to cellar");
        assertEq(assets, cellarLPTBalance5, "Cellar should have all lpt now");
    }

    /// Generic Helpers

    function _add2PoolAssetToPriceRouter(
        address pool,
        address token,
        bool isCorrelated,
        uint256 expectedPrice,
        ERC20 underlyingOrConstituent0,
        ERC20 underlyingOrConstituent1,
        bool divideRate0,
        bool divideRate1,
        uint32 lowerBound,
        uint32 upperBound
    ) internal {
        Curve2PoolExtension.ExtensionStorage memory stor;
        stor.pool = pool;
        stor.isCorrelated = isCorrelated;
        stor.underlyingOrConstituent0 = address(underlyingOrConstituent0);
        stor.underlyingOrConstituent1 = address(underlyingOrConstituent1);
        stor.divideRate0 = divideRate0;
        stor.divideRate1 = divideRate1;
        stor.lowerBound = lowerBound;
        stor.upperBound = upperBound;
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
        mockCVXdataFeed.setMockUpdatedAt(block.timestamp);
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
