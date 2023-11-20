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

/// CRISPY Pricing imports above copied over (TODO: delete your copy of his imported files (`WstEthExtension.sol, CurveEMAExtension.sol, Curve2PoolExtension.sol`) and `git pull` his actual files from dev branch ONCE he's merged his changes to it).

/**
 * @title ConvexCurveAdaptorTest
 * @author crispymangoes, 0xEinCodes
 * @notice Cellar Adaptor tests with Convex-Curve markets
 * TODO: write tests for pools of interest for ITB
 *  - Mock datafeeds to be used for underlying LPTs. Actual testing of the LPT pricing is carried out. Hash out which LPT pair to go with, and what mock datafeeds to use for constituent assets of the pair so we can warp forward to simulate reward accrual.
 * TODO: write tests for other pools of interest
 */
contract ConvexCurveAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

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

    // Chainlink PriceFeeds
    // MockDataFeed private mockMkUSDFraxBP_CRVLPT_USDFeed;
    // MockDataFeed private mockEth_STETH_CRVLPT_USDFeed;

    // TODO: add curve lpt pricing extension when it is ready. Likely just using 2Pool Pricing, or EMA pricing that Crispy has set up with his pools.
    WstEthExtension private wstethExtension;
    CurveEMAExtension private curveEMAExtension;
    Curve2PoolExtension private curve2PoolExtension;

    // // base asset within cellars are the lpts, so we'll just deal lpts to the users to deposit into the cellar. So we need a position for that, and a position for the adaptors w/ pids & baseRewardPool specs.
    // uint32 private mkUSDFraxBP_CRVLPT_Position = 1;
    // uint32 private eth_STETH_CRVLPT_Position = 2;
    // uint32 private cvxPool_mkUSDFraxBP_Position = 3;
    // uint32 private cvxPool_STETH_CRVLPT_Position = 4;

    /// CRISPY Pricing start
    MockDataFeed public mockWETHdataFeed;
    MockDataFeed public mockUSDCdataFeed;
    MockDataFeed public mockDAI_dataFeed;
    MockDataFeed public mockUSDTdataFeed;
    MockDataFeed public mockFRAXdataFeed;
    MockDataFeed public mockSTETHdataFeed;
    MockDataFeed public mockRETHdataFeed;

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

    uint32 private EthFrxethPoolPosition = 12; // https://www.convexfinance.com/stake/ethereum/128
    uint32 private EthStethNgPoolPosition = 13;
    uint32 private fraxCrvUsdPoolPosition = 14;
    uint32 private mkUsdFraxUsdcPoolPosition = 15;
    uint32 private WethYethPoolPosition = 16;
    uint32 private EthEthxPoolPosition = 17;
    uint32 private CrvUsdSfraxPoolPosition = 18;

    uint32 private slippage = 0.9e4;
    uint256 public initialAssets;

    /// CRISPY Pricing end

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18538479; // TODO: change or delete this comment. Crispy tests has blockNumber = 18492720
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        /// CRISPY Pricing start

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
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockSTETdataFeed));
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

        // Add positions to registry.

        /// CRISPY Pricing end

        deal(address(EthStethNgToken), address(this), 10e18);
        deal(address(mkUSDFraxBP_CRVLPT), address(this), 10e18);

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
            abi.encode(128, 0xbD5445402B0a287cbC77cb67B2a52e2FC635dce4)
        );
        registry.trustPosition(
            EthStethNgPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(177, 0x6B27D7BC63F1999D14fF9bA900069ee516669ee8)
        );
        registry.trustPosition(
            fraxCrvUsdPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(187, 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00)
        );
        registry.trustPosition(
            mkUsdFraxUsdcPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(225, 0x35FbE5520E70768DCD6E3215Ed54E14CBccA10D2)
        );
        registry.trustPosition(
            WethYethPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(231, 0xB0867ADE998641Ab1Ff04cF5cA5e5773fA92AaE3)
        );
        registry.trustPosition(
            EthEthxPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(232, 0x399e111c7209a741B06F8F86Ef0Fdd88fC198D20)
        );
        registry.trustPosition(
            CrvUsdSfraxPoolPosition,
            address(convexCurveAdaptor),
            abi.encode(252, 0x73eA73C3a191bd05F3266eB2414609dC5Fe777a2)
        );

        registry.trustPosition(mkUSDFraxBP_CRVLPT_Position, address(erc20Adaptor), abi.encode(mkUSDFraxBP_CRVLPT));
        registry.trustPosition(eth_STETH_CRVLPT_Position, address(erc20Adaptor), abi.encode(eth_STETH_CRVLPT));
        registry.trustPosition(
            cvxPool_mkUSDFraxBP_Position,
            address(convexCurveAdaptor),
            abi.encode(mkUSDFraxBPT_ConvexPID, mkUSDFraxBP_cvxBaseRewardContract)
        );
        registry.trustPosition(
            cvxPool_STETH_CRVLPT_Position,
            address(convexCurveAdaptor),
            abi.encode(eth_STETH_ConvexPID, eth_STETH_cvxBaseRewardContract)
        );

        // Set up Cellar which will have all LPTs dealt to it for the tests w/ a baseAsset of USDC or something?
        // TODO: EIN THIS IS WHERE YOU LEFT OFF

        string memory cellarName = "Convex Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        // baseAsset is USDC, but we will deal out LPTs within the helper test function similar to CurveAdaptor.t.sol 
        cellar = _createCellar(
            cellarName,
            USDC,
            usdcPosition,
            abi.encode(0),
            initialDeposit,
            platformCut
        );

        USDC.safeApprove(address(cellar), type(uint256).max);

        for (uint32 i = 2; i < 19; ++i) cellar.addPositionToCatalogue(i);
        for (uint32 i = 2; i < 19; ++i) cellar.addPosition(0, i, abi.encode(true), false);

        cellar.setRebalanceDeviation(0.01e18);

        cellar.addAdaptorToCatalogue(address(convexCurveAdaptor));

        initialAssets = cellar.totalAssets();
    }

    
    /**
     * THINGS TO TEST (not exhaustive):
     * Deposit Tests

- check that correct amount was deposited without staking (Cellar has cvxCRVLPT) (bool set to false)

- " and that it was all staked (bool set to true)

- check that it reverts properly if attempting to deposit when not having any curve LPT

- check that depositing atop of pre-existing convex position for the cellar works

- check that staking "

- check type(uint256).max works for deposit

---

Withdraw Tests - NOTE: we are not worrying about withdrawing and NOT unwrapping. We always unwrap.

- check correct amount is withdrawn (1:1 as rewards should not be in curve LPT I think) (bool set to false)

  - Also check that, when time is rolled forward, that the CurveLPTs obtained have not changed from when cellar entered the position. Otherwise the assumption that 1 CurveLPT == 1cvxCurveLPT == 1StakedcvxCurveLPT is invalid and `withdrawableFrom()` and `balanceOf()` likely needs to be updated

- check correct amount is withdrawn and rewards are claimed (bool set to true)

- check type(uint256).max works for withdraw

- check that withdrawing partial amount works (bool set to false)

- " (bool set to true with rewards)

---

balanceOf() tests

- Check that the right amount of curve LPTs are being accounted for (during phases where cellar has deposit and stake positions, and phases where it does not, and phases where it has a mix)

---

claimRewards() tests

- Check that we get all the CRV, CVX, 3CRV rewards we're supposed to get --> this will require testing a couple convex markets that are currently giving said rewards. **Will need to specify the block number we're starting at**

From looking over Cellar.sol, withdrawableFrom() can include staked cvxCurveLPTs. For now I am assuming that they are 1:1 w/ curveLPTs but the tests will show that or not. \* withdrawInOrder() goes through positions and ultimately calls `withdraw()` for the respective position. \_calculateTotalAssetsOrTotalAssetsWithdrawable() uses withdrawableFrom() to calculate the amount of assets there are available to withdraw from the cellar.

     */

    /// Extra pricing code that I commented out from Crispy's curve tests for now

    // uint32 private usdtPosition = 4;
    // uint32 private rethPosition = 4;
    // uint32 private oethPosition = 21;
    // uint32 private sDaiPosition = 27;
    // uint32 private sFraxPosition = 28;
    // uint32 private UsdcCrvUsdPoolPosition = 10;
    // uint32 private WethRethPoolPosition = 11;
    // uint32 private UsdtCrvUsdPoolPosition = 12;
    // uint32 private EthStethPoolPosition = 13;
    // uint32 private FraxUsdcPoolPosition = 14;
    // uint32 private WethFrxethPoolPosition = 15;
    // uint32 private StethFrxethPoolPosition = 17;
    // uint32 private WethCvxPoolPosition = 18;
    // uint32 private EthOethPoolPosition = 20;
    // uint32 private CrvUsdSdaiPoolPosition = 31;

    // // Add rETH pricing.
    // stor.inETH = true;
    // price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
    // price = priceRouter.getValue(WETH, price, USDC);
    // price = price.changeDecimals(6, 8);
    // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockRETHdataFeed));
    // priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

    // // Add CVX
    // cStor.pool = WethCvxPool;
    // cStor.index = 0;
    // cStor.needIndex = false;
    // price = curveEMAExtension.getPriceFromCurvePool(
    //     CurvePool(cStor.pool),
    //     cStor.index,
    //     cStor.needIndex,
    //     cStor.rateIndex,
    //     cStor.handleRate
    // );
    // price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
    // settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
    // priceRouter.addAsset(CVX, settings, abi.encode(cStor), price);

    // // Add OETH
    // cStor.pool = EthOethPool;
    // cStor.index = 0;
    // cStor.needIndex = false;
    // price = curveEMAExtension.getPriceFromCurvePool(
    //     CurvePool(cStor.pool),
    //     cStor.index,
    //     cStor.needIndex,
    //     cStor.rateIndex,
    //     cStor.handleRate
    // );
    // price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
    // settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
    // priceRouter.addAsset(OETH, settings, abi.encode(cStor), price);

    // // Add sDAI
    // cStor.pool = CrvUsdSdaiPool;
    // cStor.index = 0;
    // cStor.needIndex = false;
    // cStor.handleRate = true;
    // cStor.rateIndex = 1;
    // price = curveEMAExtension.getPriceFromCurvePool(
    //     CurvePool(cStor.pool),
    //     cStor.index,
    //     cStor.needIndex,
    //     cStor.rateIndex,
    //     cStor.handleRate
    // );
    // price = price.mulDivDown(priceRouter.getPriceInUSD(DAI), 1e18);
    // settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
    // priceRouter.addAsset(ERC20(sDAI), settings, abi.encode(cStor), price);

    // // Add sFRAX
    // cStor.pool = CrvUsdSfraxPool;
    // cStor.index = 0;
    // cStor.needIndex = false;
    // cStor.handleRate = true;
    // cStor.rateIndex = 1;
    // price = curveEMAExtension.getPriceFromCurvePool(
    //     CurvePool(cStor.pool),
    //     cStor.index,
    //     cStor.needIndex,
    //     cStor.rateIndex,
    //     cStor.handleRate
    // );
    // price = price.mulDivDown(priceRouter.getPriceInUSD(FRAX), 1e18);
    // settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
    // priceRouter.addAsset(ERC20(sFRAX), settings, abi.encode(cStor), price);

    // // Add 2pools.
    // // UsdcCrvUsdPool
    // // UsdcCrvUsdToken
    // // UsdcCrvUsdGauge
    // _add2PoolAssetToPriceRouter(UsdcCrvUsdPool, UsdcCrvUsdToken, true, 1e8, USDC, CRVUSD, false, false);
    // // WethRethPool
    // // WethRethToken
    // // WethRethGauge
    // _add2PoolAssetToPriceRouter(WethRethPool, WethRethToken, false, 3_863e8, WETH, rETH, false, false);
    // // UsdtCrvUsdPool
    // // UsdtCrvUsdToken
    // // UsdtCrvUsdGauge
    // _add2PoolAssetToPriceRouter(UsdtCrvUsdPool, UsdtCrvUsdToken, true, 1e8, USDT, CRVUSD, false, false);
    // // EthStethPool
    // // EthStethToken
    // // EthStethGauge
    // _add2PoolAssetToPriceRouter(EthStethPool, EthStethToken, true, 1956e8, WETH, STETH, false, false);
    // // FraxUsdcPool
    // // FraxUsdcToken
    // // FraxUsdcGauge
    // _add2PoolAssetToPriceRouter(FraxUsdcPool, FraxUsdcToken, true, 1e8, FRAX, USDC, false, false);

    // // StethFrxethPool
    // // StethFrxethToken
    // // StethFrxethGauge
    // _add2PoolAssetToPriceRouter(StethFrxethPool, StethFrxethToken, true, 1825e8, STETH, FRXETH, false, false);
    // // WethCvxPool
    // // WethCvxToken
    // // WethCvxGauge
    // _add2PoolAssetToPriceRouter(WethCvxPool, WethCvxToken, false, 154e8, WETH, CVX, false, false);
    // // EthOethPool
    // // EthOethToken
    // // EthOethGauge
    // _add2PoolAssetToPriceRouter(EthOethPool, EthOethToken, true, 1_800e8, WETH, OETH, false, false);

    // // CrvUsdSdaiPool
    // // CrvUsdSdaiToken
    // // CrvUsdSdaiGauge
    // _add2PoolAssetToPriceRouter(CrvUsdSdaiPool, CrvUsdSdaiToken, true, 1e8, CRVUSD, DAI, false, false);
    // // CrvUsdSfraxPool
    // // CrvUsdSfraxToken
    // // CrvUsdSfraxGauge
    // _add2PoolAssetToPriceRouter(CrvUsdSfraxPool, CrvUsdSfraxToken, true, 1e8, CRVUSD, FRAX, false, false);
}
