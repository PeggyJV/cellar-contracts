// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { CellarWithOracle } from "src/base/permutations/CellarWithOracle.sol";
import { MockCellarWithOracle } from "src/mocks/MockCellarWithOracle.sol";
import { CurveEMAExtension } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";
import { CurveAdaptor, CurvePool, CurveGauge, CurveHelper } from "src/modules/adaptors/Curve/CurveAdaptor.sol";
import { Curve2PoolExtension } from "src/modules/price-router/Extensions/Curve/Curve2PoolExtension.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CurveAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;
    using SafeTransferLib for address;

    CurveAdaptor private curveAdaptor;
    WstEthExtension private wstethExtension;
    CurveEMAExtension private curveEMAExtension;
    Curve2PoolExtension private curve2PoolExtension;

    Cellar private cellar;

    MockDataFeed public mockWETHdataFeed;
    MockDataFeed public mockUSDCdataFeed;
    MockDataFeed public mockDAI_dataFeed;
    MockDataFeed public mockUSDTdataFeed;
    MockDataFeed public mockFRAXdataFeed;
    MockDataFeed public mockSTETdataFeed;
    MockDataFeed public mockRETHdataFeed;

    uint32 private usdcPosition = 1;
    uint32 private crvusdPosition = 2;
    uint32 private wethPosition = 3;
    uint32 private rethPosition = 4;
    uint32 private usdtPosition = 5;
    uint32 private stethPosition = 6;
    uint32 private fraxPosition = 7;
    uint32 private frxethPosition = 8;
    uint32 private cvxPosition = 9;
    uint32 private oethPosition = 21;
    uint32 private mkUsdPosition = 23;
    uint32 private yethPosition = 25;
    uint32 private ethXPosition = 26;
    uint32 private sDaiPosition = 27;
    uint32 private sFraxPosition = 28;
    uint32 private UsdcCrvUsdPoolPosition = 10;
    uint32 private WethRethPoolPosition = 11;
    uint32 private UsdtCrvUsdPoolPosition = 12;
    uint32 private EthStethPoolPosition = 13;
    uint32 private FraxUsdcPoolPosition = 14;
    uint32 private WethFrxethPoolPosition = 15;
    uint32 private EthFrxethPoolPosition = 16;
    uint32 private StethFrxethPoolPosition = 17;
    uint32 private WethCvxPoolPosition = 18;
    uint32 private EthStethNgPoolPosition = 19;
    uint32 private EthOethPoolPosition = 20;
    uint32 private fraxCrvUsdPoolPosition = 22;
    uint32 private mkUsdFraxUsdcPoolPosition = 24;
    uint32 private WethYethPoolPosition = 29;
    uint32 private EthEthxPoolPosition = 30;
    uint32 private CrvUsdSdaiPoolPosition = 31;
    uint32 private CrvUsdSfraxPoolPosition = 32;

    uint32 private slippage = 0.9e4;
    uint256 public initialAssets;

    bool public attackCellar;
    bool public blockExternalReceiver;
    uint256 public slippageToCharge;
    address public slippageToken;

    uint8 public decimals;

    mapping(uint256 => bool) public isPositionUsed;

    // Variables were originally memory but changed to state, to prevent stack too deep errors.
    ERC20[] public coins = new ERC20[](2);
    ERC20[] tokens = new ERC20[](2);
    uint256[] balanceDelta = new uint256[](2);
    uint256[] orderedTokenAmounts = new uint256[](2);
    uint256 expectedValueOut;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18492720;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockWETHdataFeed = new MockDataFeed(WETH_USD_FEED);
        mockUSDCdataFeed = new MockDataFeed(USDC_USD_FEED);
        mockDAI_dataFeed = new MockDataFeed(DAI_USD_FEED);
        mockUSDTdataFeed = new MockDataFeed(USDT_USD_FEED);
        mockFRAXdataFeed = new MockDataFeed(FRAX_USD_FEED);
        mockSTETdataFeed = new MockDataFeed(STETH_USD_FEED);
        mockRETHdataFeed = new MockDataFeed(RETH_ETH_FEED);

        curveAdaptor = new CurveAdaptor(address(WETH), slippage);
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

        // Add rETH pricing.
        stor.inETH = true;
        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockRETHdataFeed));
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

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
        cStor.lowerBound = .95e4;
        cStor.upperBound = 1.05e4;
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
        cStor.lowerBound = .95e4;
        cStor.upperBound = 1.05e4;
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

        // Add CVX
        cStor.pool = WethCvxPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.lowerBound = 0;
        cStor.upperBound = 1e4;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(CVX, settings, abi.encode(cStor), price);

        // Add OETH
        cStor.pool = EthOethPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.lowerBound = .95e4;
        cStor.upperBound = 1.05e4;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(OETH, settings, abi.encode(cStor), price);

        // Add mkUsd
        cStor.pool = WethMkUsdPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.lowerBound = 0;
        cStor.upperBound = 1.05e4;
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
        cStor.lowerBound = .95e4;
        cStor.upperBound = 1.05e4;
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

        // Add sDAI
        cStor.pool = CrvUsdSdaiPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.handleRate = true;
        cStor.rateIndex = 1;
        cStor.lowerBound = 0;
        cStor.upperBound = 1.05e4;
        price = curveEMAExtension.getPriceFromCurvePool(
            CurvePool(cStor.pool),
            cStor.index,
            cStor.needIndex,
            cStor.rateIndex,
            cStor.handleRate
        );
        price = price.mulDivDown(priceRouter.getPriceInUSD(DAI), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(ERC20(sDAI), settings, abi.encode(cStor), price);

        // Add sFRAX
        cStor.pool = CrvUsdSfraxPool;
        cStor.index = 0;
        cStor.needIndex = false;
        cStor.handleRate = true;
        cStor.rateIndex = 1;
        cStor.lowerBound = 0;
        cStor.upperBound = 1.05e4;
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

        // Add 2pools.
        // UsdcCrvUsdPool
        // UsdcCrvUsdToken
        // UsdcCrvUsdGauge
        _add2PoolAssetToPriceRouter(UsdcCrvUsdPool, UsdcCrvUsdToken, true, 1e8, USDC, CRVUSD, false, false, 0, 10e4);
        // WethRethPool
        // WethRethToken
        // WethRethGauge
        _add2PoolAssetToPriceRouter(WethRethPool, WethRethToken, false, 3_863e8, WETH, rETH, false, false, 0, 10e4);
        // UsdtCrvUsdPool
        // UsdtCrvUsdToken
        // UsdtCrvUsdGauge
        _add2PoolAssetToPriceRouter(UsdtCrvUsdPool, UsdtCrvUsdToken, true, 1e8, USDT, CRVUSD, false, false, 0, 10e4);
        // EthStethPool
        // EthStethToken
        // EthStethGauge
        _add2PoolAssetToPriceRouter(EthStethPool, EthStethToken, true, 1956e8, WETH, STETH, false, false, 0, 10e4);
        // FraxUsdcPool
        // FraxUsdcToken
        // FraxUsdcGauge
        _add2PoolAssetToPriceRouter(FraxUsdcPool, FraxUsdcToken, true, 1e8, FRAX, USDC, false, false, 0, 10e4);
        // WethFrxethPool
        // WethFrxethToken
        // WethFrxethGauge
        _add2PoolAssetToPriceRouter(WethFrxethPool, WethFrxethToken, true, 1800e8, WETH, FRXETH, false, false, 0, 10e4);
        // EthFrxethPool
        // EthFrxethToken
        // EthFrxethGauge
        _add2PoolAssetToPriceRouter(EthFrxethPool, EthFrxethToken, true, 1800e8, WETH, FRXETH, false, false, 0, 10e4);
        // StethFrxethPool
        // StethFrxethToken
        // StethFrxethGauge
        _add2PoolAssetToPriceRouter(
            StethFrxethPool,
            StethFrxethToken,
            true,
            1825e8,
            STETH,
            FRXETH,
            false,
            false,
            0,
            10e4
        );
        // WethCvxPool
        // WethCvxToken
        // WethCvxGauge
        _add2PoolAssetToPriceRouter(WethCvxPool, WethCvxToken, false, 154e8, WETH, CVX, false, false, 0, 10e4);
        // EthStethNgPool
        // EthStethNgToken
        // EthStethNgGauge
        _add2PoolAssetToPriceRouter(EthStethNgPool, EthStethNgToken, true, 1_800e8, WETH, STETH, false, false, 0, 10e4);
        // EthOethPool
        // EthOethToken
        // EthOethGauge
        _add2PoolAssetToPriceRouter(EthOethPool, EthOethToken, true, 1_800e8, WETH, OETH, false, false, 0, 10e4);
        // FraxCrvUsdPool
        // FraxCrvUsdToken
        // FraxCrvUsdGauge
        _add2PoolAssetToPriceRouter(FraxCrvUsdPool, FraxCrvUsdToken, true, 1e8, FRAX, CRVUSD, false, false, 0, 10e4);
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
        // WethYethPool
        // WethYethToken
        // WethYethGauge
        _add2PoolAssetToPriceRouter(WethYethPool, WethYethToken, true, 1_800e8, WETH, YETH, false, false, 0, 10e4);
        // EthEthxPool
        // EthEthxToken
        // EthEthxGauge
        _add2PoolAssetToPriceRouter(EthEthxPool, EthEthxToken, true, 1_800e8, WETH, ETHX, false, true, 0, 10e4);

        // CrvUsdSdaiPool
        // CrvUsdSdaiToken
        // CrvUsdSdaiGauge
        _add2PoolAssetToPriceRouter(CrvUsdSdaiPool, CrvUsdSdaiToken, true, 1e8, CRVUSD, DAI, false, false, 0, 10e4);
        // CrvUsdSfraxPool
        // CrvUsdSfraxToken
        // CrvUsdSfraxGauge
        _add2PoolAssetToPriceRouter(CrvUsdSfraxPool, CrvUsdSfraxToken, true, 1e8, CRVUSD, FRAX, false, false, 0, 10e4);

        // Add positions to registry.
        registry.trustAdaptor(address(curveAdaptor));

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(crvusdPosition, address(erc20Adaptor), abi.encode(CRVUSD));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(rethPosition, address(erc20Adaptor), abi.encode(rETH));
        registry.trustPosition(usdtPosition, address(erc20Adaptor), abi.encode(USDT));
        registry.trustPosition(stethPosition, address(erc20Adaptor), abi.encode(STETH));
        registry.trustPosition(fraxPosition, address(erc20Adaptor), abi.encode(FRAX));
        registry.trustPosition(frxethPosition, address(erc20Adaptor), abi.encode(FRXETH));
        registry.trustPosition(cvxPosition, address(erc20Adaptor), abi.encode(CVX));
        registry.trustPosition(oethPosition, address(erc20Adaptor), abi.encode(OETH));
        registry.trustPosition(mkUsdPosition, address(erc20Adaptor), abi.encode(MKUSD));
        registry.trustPosition(yethPosition, address(erc20Adaptor), abi.encode(YETH));
        registry.trustPosition(ethXPosition, address(erc20Adaptor), abi.encode(ETHX));
        registry.trustPosition(sDaiPosition, address(erc20Adaptor), abi.encode(sDAI));
        registry.trustPosition(sFraxPosition, address(erc20Adaptor), abi.encode(sFRAX));

        // Below position shoudl technically be illiquid bc the re-entrancy function doesnt actually check for
        // re-entrancy, but for the sake of not refactoring a large test, it has been left alone.
        registry.trustPosition(
            UsdcCrvUsdPoolPosition,
            address(curveAdaptor),
            abi.encode(UsdcCrvUsdPool, UsdcCrvUsdToken, UsdcCrvUsdGauge, CurvePool.withdraw_admin_fees.selector)
        );
        registry.trustPosition(
            WethRethPoolPosition,
            address(curveAdaptor),
            abi.encode(WethRethPool, WethRethToken, WethRethGauge, CurvePool.claim_admin_fees.selector)
        );
        // Does not check for re-entrancy.
        registry.trustPosition(
            UsdtCrvUsdPoolPosition,
            address(curveAdaptor),
            abi.encode(UsdtCrvUsdPool, UsdtCrvUsdToken, UsdtCrvUsdGauge, CurvePool.withdraw_admin_fees.selector)
        );
        // No valid functions to call to check for re-entrancy.
        registry.trustPosition(
            EthStethPoolPosition,
            address(curveAdaptor),
            abi.encode(EthStethPool, EthStethToken, EthStethGauge, bytes4(0))
        );
        // Does not check for re-entrancy.
        registry.trustPosition(
            FraxUsdcPoolPosition,
            address(curveAdaptor),
            abi.encode(FraxUsdcPool, FraxUsdcToken, FraxUsdcGauge, CurvePool.withdraw_admin_fees.selector)
        );
        // No valid functions to call to check for re-entrancy.
        registry.trustPosition(
            WethFrxethPoolPosition,
            address(curveAdaptor),
            abi.encode(WethFrxethPool, WethFrxethToken, WethFrxethGauge, CurvePool.withdraw_admin_fees.selector)
        );
        registry.trustPosition(
            EthFrxethPoolPosition,
            address(curveAdaptor),
            abi.encode(
                EthFrxethPool,
                EthFrxethToken,
                EthFrxethGauge,
                bytes4(keccak256(abi.encodePacked("price_oracle()")))
            )
        );
        // Does not check for re-entrancy.
        registry.trustPosition(
            StethFrxethPoolPosition,
            address(curveAdaptor),
            abi.encode(StethFrxethPool, StethFrxethToken, StethFrxethGauge, CurvePool.withdraw_admin_fees.selector)
        );
        registry.trustPosition(
            WethCvxPoolPosition,
            address(curveAdaptor),
            abi.encode(WethCvxPool, WethCvxToken, WethCvxGauge, CurvePool.claim_admin_fees.selector)
        );

        registry.trustPosition(
            EthStethNgPoolPosition,
            address(curveAdaptor),
            abi.encode(EthStethNgPool, EthStethNgToken, EthStethNgGauge, CurvePool.withdraw_admin_fees.selector)
        );

        registry.trustPosition(
            EthOethPoolPosition,
            address(curveAdaptor),
            abi.encode(EthOethPool, EthOethToken, EthOethGauge, CurvePool.withdraw_admin_fees.selector)
        );

        // Does not check for re-entrancy.
        registry.trustPosition(
            fraxCrvUsdPoolPosition,
            address(curveAdaptor),
            abi.encode(FraxCrvUsdPool, FraxCrvUsdToken, FraxCrvUsdGauge, CurvePool.withdraw_admin_fees.selector)
        );

        // Does not check for re-entrancy.
        registry.trustPosition(
            mkUsdFraxUsdcPoolPosition,
            address(curveAdaptor),
            abi.encode(
                mkUsdFraxUsdcPool,
                mkUsdFraxUsdcToken,
                mkUsdFraxUsdcGauge,
                CurvePool.withdraw_admin_fees.selector
            )
        );

        registry.trustPosition(
            WethYethPoolPosition,
            address(curveAdaptor),
            abi.encode(WethYethPool, WethYethToken, WethYethGauge, CurvePool.withdraw_admin_fees.selector)
        );

        registry.trustPosition(
            EthEthxPoolPosition,
            address(curveAdaptor),
            abi.encode(EthEthxPool, EthEthxToken, EthEthxGauge, CurvePool.withdraw_admin_fees.selector)
        );

        // Does not check for re-entrancy.
        registry.trustPosition(
            CrvUsdSdaiPoolPosition,
            address(curveAdaptor),
            abi.encode(CrvUsdSdaiPool, CrvUsdSdaiToken, CrvUsdSdaiGauge, CurvePool.withdraw_admin_fees.selector)
        );

        // Does not check for re-entrancy.
        registry.trustPosition(
            CrvUsdSfraxPoolPosition,
            address(curveAdaptor),
            abi.encode(CrvUsdSfraxPool, CrvUsdSfraxToken, CrvUsdSfraxGauge, CurvePool.withdraw_admin_fees.selector)
        );

        string memory cellarName = "Curve Cellar V0.0";
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
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );
        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(curveAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        for (uint32 i = 2; i < 33; ++i) cellar.addPositionToCatalogue(i);
        for (uint32 i = 2; i < 33; ++i) cellar.addPosition(0, i, abi.encode(true), false);

        cellar.setRebalanceDeviation(0.030e18);

        initialAssets = cellar.totalAssets();

        // Used so that this address can be used as a "cellar" and spoof the validation check in adaptor.
        isPositionUsed[0] = true;
    }

    // ========================================= HAPPY PATH TESTS =========================================

    function testManagingLiquidityIn2PoolNoETH0(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            UsdcCrvUsdPool,
            UsdcCrvUsdToken,
            UsdcCrvUsdGauge,
            0.0005e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH1(uint256 assets) external {
        // Pool only has 6M TVL so it experiences very high slippage.
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            WethRethPool,
            WethRethToken,
            WethRethGauge,
            0.0005e18,
            CurvePool.claim_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH2(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            UsdtCrvUsdPool,
            UsdtCrvUsdToken,
            UsdtCrvUsdGauge,
            0.0005e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH3(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            FraxUsdcPool,
            FraxUsdcToken,
            FraxUsdcGauge,
            0.0005e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH4(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            WethFrxethPool,
            WethFrxethToken,
            WethFrxethGauge,
            0.0005e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH5(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            StethFrxethPool,
            StethFrxethToken,
            StethFrxethGauge,
            0.0010e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH6(uint256 assets) external {
        // Pool has a very high fee.
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            WethCvxPool,
            WethCvxToken,
            WethCvxGauge,
            0.0050e18,
            CurvePool.claim_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH7(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            FraxCrvUsdPool,
            FraxCrvUsdToken,
            FraxCrvUsdGauge,
            0.0005e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH8(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            mkUsdFraxUsdcPool,
            mkUsdFraxUsdcToken,
            mkUsdFraxUsdcGauge,
            0.0050e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH9(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            WethYethPool,
            WethYethToken,
            WethYethGauge,
            0.0050e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH10(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            CrvUsdSdaiPool,
            CrvUsdSdaiToken,
            CrvUsdSdaiGauge,
            0.0010e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolNoETH11(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(
            assets,
            CrvUsdSfraxPool,
            CrvUsdSfraxToken,
            CrvUsdSfraxGauge,
            0.0010e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolWithETH0(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _manageLiquidityIn2PoolWithETH(assets, EthStethPool, EthStethToken, EthStethGauge, 0.0030e18, bytes4(0));
    }

    function testManagingLiquidityIn2PoolWithETH1(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _manageLiquidityIn2PoolWithETH(
            assets,
            EthFrxethPool,
            EthFrxethToken,
            EthFrxethGauge,
            0.0010e18,
            bytes4(keccak256(abi.encodePacked("price_oracle()")))
        );
    }

    function testManagingLiquidityIn2PoolWithETH2(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _manageLiquidityIn2PoolWithETH(
            assets,
            EthStethNgPool,
            EthStethNgToken,
            EthStethNgGauge,
            0.0025e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolWithETH3(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _manageLiquidityIn2PoolWithETH(
            assets,
            EthOethPool,
            EthOethToken,
            EthOethGauge,
            0.0010e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testManagingLiquidityIn2PoolWithETH4(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolWithETH(
            assets,
            EthEthxPool,
            EthEthxToken,
            EthEthxGauge,
            0.0020e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    // `withdraw_admin_fees` does not perform a re-entrancy check :(
    // function testDepositAndWithdrawFromCurveLP0(uint256 assets) external {
    //     assets = bound(assets, 1e18, 1_000_000e18);
    //     _curveLPAsAccountingAsset(assets, ERC20(UsdcCrvUsdToken), UsdcCrvUsdPoolPosition, UsdcCrvUsdGauge);
    // }

    function testDepositAndWithdrawFromCurveLP1(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(WethRethToken), WethRethPoolPosition, WethRethGauge);
    }

    function testDepositAndWithdrawFromCurveLP2(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(UsdtCrvUsdToken), UsdtCrvUsdPoolPosition, UsdtCrvUsdGauge);
    }

    function testDepositAndWithdrawFromCurveLP3(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(StethFrxethToken), StethFrxethPoolPosition, StethFrxethGauge);
    }

    function testDepositAndWithdrawFromCurveLP4(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(WethFrxethToken), WethFrxethPoolPosition, WethFrxethGauge);
    }

    function testDepositAndWithdrawFromCurveLP5(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(WethCvxToken), WethCvxPoolPosition, WethCvxGauge);
    }

    function testDepositAndWithdrawFromCurveLP6(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(EthFrxethToken), EthFrxethPoolPosition, EthFrxethGauge);
    }

    function testDepositAndWithdrawFromCurveLP7(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(EthOethToken), EthOethPoolPosition, EthOethGauge);
    }

    function testDepositAndWithdrawFromCurveLP8(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(EthStethNgToken), EthStethNgPoolPosition, EthStethNgGauge);
    }

    function testDepositAndWithdrawFromCurveLP9(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(FraxCrvUsdToken), fraxCrvUsdPoolPosition, FraxCrvUsdGauge);
    }

    function testDepositAndWithdrawFromCurveLP10(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(mkUsdFraxUsdcToken), mkUsdFraxUsdcPoolPosition, mkUsdFraxUsdcGauge);
    }

    function testDepositAndWithdrawFromCurveLP11(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(WethYethToken), WethYethPoolPosition, WethYethGauge);
    }

    function testDepositAndWithdrawFromCurveLP12(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(EthEthxToken), EthEthxPoolPosition, EthEthxGauge);
    }

    function testDepositAndWithdrawFromCurveLP13(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(CrvUsdSdaiToken), CrvUsdSdaiPoolPosition, CrvUsdSdaiGauge);
    }

    function testDepositAndWithdrawFromCurveLP14(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000e18);
        _curveLPAsAccountingAsset(assets, ERC20(CrvUsdSfraxToken), CrvUsdSfraxPoolPosition, CrvUsdSfraxGauge);
    }

    function testWithdrawLogic(uint256 assets) external {
        assets = bound(assets, 100e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        // Remove CrvUsdSfraxPoolPosition, and re-add it as illiquid.
        cellar.removePosition(0, false);
        cellar.addPosition(0, CrvUsdSfraxPoolPosition, abi.encode(false), false);

        // Split assets in half
        assets = assets / 2;

        // NOTE vanilla USDC is already at the end of the queue.

        // Deposit 1/2 of the assets in the cellar.
        cellar.deposit(assets, address(this));

        // Simulate liquidity addition into UsdcCrvUsd Pool.
        uint256 lpAmount = priceRouter.getValue(USDC, assets, ERC20(UsdcCrvUsdToken));
        deal(address(USDC), address(cellar), initialAssets);
        deal(UsdcCrvUsdToken, address(cellar), lpAmount);

        uint256 totalAssetsWithdrawable = cellar.totalAssetsWithdrawable();
        uint256 totalAssets = cellar.totalAssets();
        assertEq(totalAssetsWithdrawable, totalAssets, "All assets should be liquid.");

        // Have user withdraw all their assets.
        uint256 sharesToRedeem = cellar.maxRedeem(address(this));
        cellar.redeem(sharesToRedeem, address(this), address(this));
        uint256 lpTokensReceived = ERC20(UsdcCrvUsdToken).balanceOf(address(this));
        uint256 valueReceived = priceRouter.getValue(ERC20(UsdcCrvUsdToken), lpTokensReceived, USDC);
        assertApproxEqAbs(valueReceived, assets, 3, "User should have received assets worth of value out.");

        // Deposit 1/2 of the assets in the cellar.
        cellar.deposit(assets, address(this));

        // Simulate liquidity addition into CrvUsdSfrax Pool.
        lpAmount = priceRouter.getValue(USDC, assets, ERC20(CrvUsdSfraxToken));
        deal(address(USDC), address(cellar), initialAssets);
        deal(CrvUsdSfraxToken, address(cellar), lpAmount);

        totalAssetsWithdrawable = cellar.totalAssetsWithdrawable();
        assertApproxEqAbs(totalAssetsWithdrawable, initialAssets, 3, "Only initial assets should be liquid.");

        // If a cellar tried to withdraw from the Curve Position it would revert.
        bytes memory data = abi.encodeWithSelector(
            CurveAdaptor.withdraw.selector,
            lpAmount,
            address(1),
            abi.encode(CrvUsdSfraxPool, CrvUsdSfraxToken, CrvUsdSfraxGauge, CurvePool.get_virtual_price.selector),
            abi.encode(false)
        );

        vm.expectRevert();
        address(curveAdaptor).functionDelegateCall(data);

        // Simulate liquidity addition into EthSteth Pool.
        lpAmount = priceRouter.getValue(USDC, assets, ERC20(EthStethToken));
        deal(CrvUsdSfraxToken, address(cellar), 0);
        deal(EthStethToken, address(cellar), lpAmount);

        totalAssetsWithdrawable = cellar.totalAssetsWithdrawable();
        assertApproxEqAbs(totalAssetsWithdrawable, initialAssets, 3, "Only initial assets should be liquid.");

        // If a cellar tried to withdraw from the Curve Position it would revert.
        data = abi.encodeWithSelector(
            CurveAdaptor.withdraw.selector,
            lpAmount,
            address(1),
            abi.encode(EthStethPool, EthStethToken, EthStethGauge, bytes4(0)),
            abi.encode(true)
        );

        vm.expectRevert();
        address(curveAdaptor).functionDelegateCall(data);
    }

    // ========================================= Reverts =========================================

    // function testWithdrawWithReentrancy0(uint256 assets) external {
    //     assets = bound(assets, 1e6, 1_000_000e6);
    //     _checkForReentrancyOnWithdraw(assets, EthStethPool, EthStethToken);
    // }

    function testWithdrawWithReentrancy1(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _checkForReentrancyOnWithdraw(
            assets,
            EthFrxethPool,
            EthFrxethToken,
            EthFrxethGauge,
            bytes4(keccak256(abi.encodePacked("price_oracle()")))
        );
    }

    function testWithdrawWithReentrancy2(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _checkForReentrancyOnWithdraw(
            assets,
            EthStethNgPool,
            EthStethNgToken,
            EthStethNgGauge,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testWithdrawWithReentrancy3(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _checkForReentrancyOnWithdraw(
            assets,
            EthOethPool,
            EthOethToken,
            EthOethGauge,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testWithdrawWithReentrancy4(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _checkForReentrancyOnWithdraw(
            assets,
            EthEthxPool,
            EthEthxToken,
            EthEthxGauge,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    function testSlippageRevertsNoETH(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);

        // WethFrxethPoolPosition

        // Add new Curve LP position where pool is set to this address.
        uint32 newWethFrxethPoolPosition = 777;
        registry.trustPosition(
            newWethFrxethPoolPosition,
            address(curveAdaptor),
            abi.encode(address(this), WethFrxethToken, WethFrxethGauge, CurvePool.withdraw_admin_fees.selector)
        );

        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        cellar.addPositionToCatalogue(newWethFrxethPoolPosition);
        cellar.removePosition(0, false);
        cellar.addPosition(0, newWethFrxethPoolPosition, abi.encode(true), false);

        ERC20 coins0 = ERC20(CurvePool(WethFrxethPool).coins(0));
        ERC20 coins1 = ERC20(CurvePool(WethFrxethPool).coins(1));

        // Convert cellars USDC balance into coins0.
        if (coins0 != USDC) {
            if (address(coins0) == curveAdaptor.CURVE_ETH()) {
                assets = priceRouter.getValue(USDC, assets, WETH);
                deal(address(WETH), address(cellar), assets);
            } else {
                assets = priceRouter.getValue(USDC, assets, coins0);
                if (coins0 == STETH) _takeSteth(assets, address(cellar));
                else if (coins0 == OETH) _takeOeth(assets, address(cellar));
                else deal(address(coins0), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), assets);
        }

        // Set up slippage variables needed to run the test
        coins[0] = coins0;
        coins[1] = coins1;
        slippageToCharge = 0.8e4;
        slippageToken = WethFrxethToken;

        // uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets / 2;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(
                address(this),
                ERC20(WethFrxethToken),
                orderedTokenAmounts,
                0,
                WethFrxethGauge,
                CurvePool.withdraw_admin_fees.selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });

            // Call reverts because of slippage.
            vm.expectRevert(bytes(abi.encodeWithSelector(CurveAdaptor.CurveAdaptor___Slippage.selector)));
            cellar.callOnAdaptor(data);

            // But if slippage is reduced, call is successful.
            slippageToCharge = 0.95e4;
            cellar.callOnAdaptor(data);
        }

        // Strategist pulls liquidity.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            orderedTokenAmounts[0] = 0;

            uint256 amountToPull = ERC20(WethFrxethToken).balanceOf(address(cellar));

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRemoveLiquidityFromCurve(
                address(this),
                ERC20(WethFrxethToken),
                amountToPull,
                orderedTokenAmounts,
                WethFrxethGauge,
                CurvePool.withdraw_admin_fees.selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });

            slippageToCharge = 0.8e4;

            // Call reverts because of slippage.
            vm.expectRevert(bytes(abi.encodeWithSelector(CurveAdaptor.CurveAdaptor___Slippage.selector)));
            cellar.callOnAdaptor(data);

            slippageToCharge = 0.95e4;
            cellar.callOnAdaptor(data);
        }
    }

    function testSlippageRevertsWithETH(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);

        // WethFrxethPoolPosition
        // EthFrxethPoolPosition

        // Add new Curve LP positions where pool is set to this address.
        uint32 newEthFrxethPoolPosition = 7777;
        registry.trustPosition(
            newEthFrxethPoolPosition,
            address(curveAdaptor),
            abi.encode(
                address(this),
                EthFrxethToken,
                EthFrxethGauge,
                bytes4(keccak256(abi.encodePacked("price_oracle()")))
            )
        );

        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        cellar.addPositionToCatalogue(newEthFrxethPoolPosition);
        cellar.removePosition(0, false);
        cellar.addPosition(0, newEthFrxethPoolPosition, abi.encode(true), false);

        ERC20 coins0 = ERC20(CurvePool(EthFrxethPool).coins(0));
        ERC20 coins1 = ERC20(CurvePool(EthFrxethPool).coins(1));

        // Convert cellars USDC balance into coins0.
        if (coins0 != USDC) {
            if (address(coins0) == curveAdaptor.CURVE_ETH()) {
                assets = priceRouter.getValue(USDC, assets, WETH);
                deal(address(WETH), address(cellar), assets);
            } else {
                assets = priceRouter.getValue(USDC, assets, coins0);
                if (coins0 == STETH) _takeSteth(assets, address(cellar));
                else if (coins0 == OETH) _takeOeth(assets, address(cellar));
                else deal(address(coins0), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), assets);
        }

        // Set up slippage variables needed to run the test
        coins[0] = coins0;
        coins[1] = coins1;
        slippageToCharge = 0.8e4;
        slippageToken = EthFrxethToken;

        // uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets / 2;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
                address(this),
                ERC20(EthFrxethToken),
                orderedTokenAmounts,
                0,
                false,
                EthFrxethGauge,
                bytes4(keccak256(abi.encodePacked("price_oracle()")))
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });

            // Call reverts because of slippage.
            vm.expectRevert(bytes(abi.encodeWithSelector(CurveAdaptor.CurveAdaptor___Slippage.selector)));
            cellar.callOnAdaptor(data);

            // But if slippage is reduced, call is successful.
            slippageToCharge = 0.95e4;
            cellar.callOnAdaptor(data);
        }

        // Reset these jsut in case they were changed in add_liquidity.
        coins[0] = coins0;
        coins[1] = coins1;

        // Strategist pulls liquidity.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            orderedTokenAmounts[0] = 0;

            uint256 amountToPull = ERC20(EthFrxethToken).balanceOf(address(cellar));

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRemoveETHLiquidityFromCurve(
                address(this),
                ERC20(EthFrxethToken),
                amountToPull,
                orderedTokenAmounts,
                false,
                EthFrxethGauge,
                bytes4(keccak256(abi.encodePacked("price_oracle()")))
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });

            slippageToCharge = 0.8e4;

            // Call reverts because of slippage.
            vm.expectRevert(bytes(abi.encodeWithSelector(CurveAdaptor.CurveAdaptor___Slippage.selector)));
            cellar.callOnAdaptor(data);

            slippageToCharge = 0.95e4;
            cellar.callOnAdaptor(data);
        }
    }

    function add_liquidity(uint256[2] memory amounts, uint256) external payable {
        // Remove amounts from caller.
        if (address(coins[0]) != curveAdaptor.CURVE_ETH()) {
            uint256 coins0Balance = coins[0].balanceOf(msg.sender);
            deal(address(coins[0]), msg.sender, coins0Balance - amounts[0]);
        } else coins[0] = WETH;
        if (address(coins[1]) != curveAdaptor.CURVE_ETH()) {
            uint256 coins1Balance = coins[1].balanceOf(msg.sender);
            deal(address(coins[1]), msg.sender, coins1Balance - amounts[1]);
        } else coins[1] = WETH;

        // Get value out.
        uint256[] memory coinAmounts = new uint256[](2);
        coinAmounts[0] = amounts[0];
        coinAmounts[1] = amounts[1];
        uint256 valueOut = priceRouter.getValues(coins, coinAmounts, ERC20(slippageToken));

        // Apply slippage.
        valueOut = valueOut.mulDivDown(slippageToCharge, 1e4);

        uint256 startingTokenBalance = ERC20(slippageToken).balanceOf(msg.sender);
        deal(slippageToken, msg.sender, startingTokenBalance + valueOut);
    }

    function remove_liquidity(uint256 lpAmount, uint256[2] memory) external {
        // Remove lpAmounts from caller.
        uint256 startingTokenBalance = ERC20(slippageToken).balanceOf(msg.sender);
        deal(slippageToken, msg.sender, startingTokenBalance - lpAmount);
        // Get value out.
        uint256 valueOut;
        if (address(coins[0]) == curveAdaptor.CURVE_ETH())
            valueOut = priceRouter.getValue(ERC20(slippageToken), lpAmount, WETH);
        else valueOut = priceRouter.getValue(ERC20(slippageToken), lpAmount, coins[0]);

        // Apply slippage.
        valueOut = valueOut.mulDivDown(slippageToCharge, 1e4);

        if (address(coins[0]) != curveAdaptor.CURVE_ETH()) {
            uint256 coins0Balance = coins[0].balanceOf(msg.sender);
            deal(address(coins[0]), msg.sender, coins0Balance + valueOut);
        } else {
            uint256 coins0Balance = msg.sender.balance;
            deal(msg.sender, coins0Balance + valueOut);
        }

        deal(address(coins[1]), msg.sender, 1);
    }

    function testReentrancyProtection0(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        bytes memory expectedRevert = bytes(
            abi.encodeWithSelector(CurveHelper.CurveHelper___PoolInReenteredState.selector)
        );
        _verifyReentrancyProtectionWorks(WethRethPool, WethRethToken, WethRethPoolPosition, assets, expectedRevert);
    }

    function testReentrancyProtection1(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        bytes memory expectedRevert;
        _verifyReentrancyProtectionWorks(EthFrxethPool, EthFrxethToken, EthFrxethPoolPosition, assets, expectedRevert);
    }

    function testReentrancyProtection2(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        bytes memory expectedRevert = bytes(
            abi.encodeWithSelector(CurveHelper.CurveHelper___PoolInReenteredState.selector)
        );
        _verifyReentrancyProtectionWorks(WethCvxPool, WethCvxToken, WethCvxPoolPosition, assets, expectedRevert);
    }

    function testReentrancyProtection3(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        bytes memory expectedRevert;
        _verifyReentrancyProtectionWorks(
            EthStethNgPool,
            EthStethNgToken,
            EthStethNgPoolPosition,
            assets,
            expectedRevert
        );
    }

    function testReentrancyProtection4(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        bytes memory expectedRevert;
        _verifyReentrancyProtectionWorks(EthOethPool, EthOethToken, EthOethPoolPosition, assets, expectedRevert);
    }

    function testReentrancyProtection5(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        bytes memory expectedRevert;
        _verifyReentrancyProtectionWorks(WethYethPool, WethYethToken, WethYethPoolPosition, assets, expectedRevert);
    }

    function testReentrancyProtection6(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        bytes memory expectedRevert;
        _verifyReentrancyProtectionWorks(EthEthxPool, EthEthxToken, EthEthxPoolPosition, assets, expectedRevert);
    }

    // ========================================= Reverts =========================================

    function testInteractingWithPositionThatIsNotUsed() external {
        bytes32 dummyPositionHash = 0xb1e0a4c60d9e010083a308f287240915af53a1fe09b8464d798e4eebd7124801;
        stdstore
            .target(address(registry))
            .sig("getPositionHashToPositionId(bytes32)")
            .with_key(dummyPositionHash)
            .checked_write(type(uint32).max);

        // Cellar tries to interact with an untrusted position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        orderedTokenAmounts[0] = 0;

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToStakeCurveLP(address(0), address(0), 0, address(0), bytes4(0));
        data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CurveAdaptor.CurveAdaptor__CurvePositionNotUsed.selector, type(uint32).max))
        );
        cellar.callOnAdaptor(data);
    }

    function testMismatchedArrayLengths() external {
        uint256[] memory orderedUnderlyingTokenAmounts = new uint256[](3);
        bytes memory data = abi.encodeWithSelector(
            CurveAdaptor.addLiquidity.selector,
            address(UsdcCrvUsdPool),
            ERC20(address(0)),
            orderedUnderlyingTokenAmounts,
            0
        );

        vm.expectRevert();
        address(curveAdaptor).functionDelegateCall(data);

        data = abi.encodeWithSelector(
            CurveAdaptor.addLiquidityETH.selector,
            address(UsdcCrvUsdPool),
            ERC20(address(0)),
            orderedUnderlyingTokenAmounts,
            0,
            false
        );

        vm.expectRevert();
        address(curveAdaptor).functionDelegateCall(data);

        data = abi.encodeWithSelector(
            CurveAdaptor.removeLiquidity.selector,
            address(UsdcCrvUsdPool),
            ERC20(address(0)),
            0,
            orderedUnderlyingTokenAmounts
        );

        vm.expectRevert();
        address(curveAdaptor).functionDelegateCall(data);

        data = abi.encodeWithSelector(
            CurveAdaptor.removeLiquidityETH.selector,
            address(UsdcCrvUsdPool),
            ERC20(address(0)),
            0,
            orderedUnderlyingTokenAmounts,
            false
        );

        vm.expectRevert();
        address(curveAdaptor).functionDelegateCall(data);

        orderedUnderlyingTokenAmounts = new uint256[](1);
        data = abi.encodeWithSelector(
            CurveAdaptor.addLiquidity.selector,
            address(UsdcCrvUsdPool),
            ERC20(address(0)),
            orderedUnderlyingTokenAmounts,
            0
        );

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___PoolHasMoreTokensThanExpected.selector))
        );
        address(curveAdaptor).functionDelegateCall(data);

        data = abi.encodeWithSelector(
            CurveAdaptor.addLiquidityETH.selector,
            address(UsdcCrvUsdPool),
            ERC20(address(0)),
            orderedUnderlyingTokenAmounts,
            0,
            false
        );

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___PoolHasMoreTokensThanExpected.selector))
        );
        address(curveAdaptor).functionDelegateCall(data);

        data = abi.encodeWithSelector(
            CurveAdaptor.removeLiquidity.selector,
            address(UsdcCrvUsdPool),
            ERC20(address(0)),
            0,
            orderedUnderlyingTokenAmounts
        );

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___PoolHasMoreTokensThanExpected.selector))
        );
        address(curveAdaptor).functionDelegateCall(data);

        data = abi.encodeWithSelector(
            CurveAdaptor.removeLiquidityETH.selector,
            address(UsdcCrvUsdPool),
            ERC20(address(0)),
            0,
            orderedUnderlyingTokenAmounts,
            false
        );

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___PoolHasMoreTokensThanExpected.selector))
        );
        address(curveAdaptor).functionDelegateCall(data);
    }

    function testUsingNormalFunctionsToInteractWithETHCurvePool() external {
        ERC20[] memory underlyingTokens = new ERC20[](2);
        underlyingTokens[0] = ERC20(curveAdaptor.CURVE_ETH());
        underlyingTokens[1] = STETH;
        uint256[] memory orderedUnderlyingTokenAmounts = new uint256[](2);
        deal(address(WETH), address(cellar), 1e18);
        orderedUnderlyingTokenAmounts[0] = 1e18;
        orderedUnderlyingTokenAmounts[1] = 0;

        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(
                EthStethPool,
                ERC20(EthStethToken),
                orderedUnderlyingTokenAmounts,
                0,
                EthStethGauge,
                bytes4(0)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            vm.expectRevert();
            cellar.callOnAdaptor(data);
        }

        _takeSteth(10e18, address(cellar));
        orderedUnderlyingTokenAmounts[0] = 0;
        orderedUnderlyingTokenAmounts[1] = 1e18;
        underlyingTokens[0] = WETH;

        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(
                EthStethPool,
                ERC20(EthStethToken),
                orderedUnderlyingTokenAmounts,
                0,
                EthStethGauge,
                bytes4(0)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            // It is technically possible to add liquidity to an ETH pair with a non ETH function.
            cellar.callOnAdaptor(data);
        }

        // But removal fails because cellar can not accept ETH.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRemoveLiquidityFromCurve(
                EthStethPool,
                ERC20(EthStethToken),
                ERC20(EthStethToken).balanceOf(address(cellar)),
                orderedUnderlyingTokenAmounts,
                EthStethGauge,
                bytes4(0)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            vm.expectRevert();
            cellar.callOnAdaptor(data);
        }
    }

    function testCellarMakingCallsToProxyFunctions() external {
        cellar.transferOwnership(gravityBridgeAddress);
        vm.startPrank(gravityBridgeAddress);
        ERC20[] memory underlyingTokens = new ERC20[](2);
        uint256[] memory orderedUnderlyingTokenAmounts = new uint256[](2);
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                CurveHelper.addLiquidityETHViaProxy.selector,
                address(0),
                address(0),
                underlyingTokens,
                orderedUnderlyingTokenAmounts,
                0,
                false
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            vm.expectRevert(
                bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___StorageSlotNotInitialized.selector))
            );
            cellar.callOnAdaptor(data);
        }
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                CurveHelper.removeLiquidityETHViaProxy.selector,
                address(0),
                address(0),
                0,
                underlyingTokens,
                orderedUnderlyingTokenAmounts,
                false
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            vm.expectRevert(
                bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___StorageSlotNotInitialized.selector))
            );
            cellar.callOnAdaptor(data);
        }
        vm.stopPrank();
    }

    function testAddingCurvePositionsWithWeirdDecimals() external {
        // We will use the test address, as the Curve token/gauge with weird decimals.
        decimals = 8;

        // First try trsuting a postion where both token and gague have weird decimals.
        vm.expectRevert(bytes(abi.encodeWithSelector(CurveAdaptor.CurveAdaptor___NonStandardDecimals.selector)));
        registry.trustPosition(
            777,
            address(curveAdaptor),
            abi.encode(address(0), address(this), address(this), CurvePool.withdraw_admin_fees.selector)
        );

        // Now try adding a position where only the token has weird decimals.
        vm.expectRevert(bytes(abi.encodeWithSelector(CurveAdaptor.CurveAdaptor___NonStandardDecimals.selector)));
        registry.trustPosition(
            777,
            address(curveAdaptor),
            abi.encode(address(0), address(this), EthStethGauge, CurvePool.withdraw_admin_fees.selector)
        );

        // Now try adding a position where only the gauge has weird decimals.
        vm.expectRevert(bytes(abi.encodeWithSelector(CurveAdaptor.CurveAdaptor___NonStandardDecimals.selector)));
        registry.trustPosition(
            777,
            address(curveAdaptor),
            abi.encode(address(0), EthStethToken, address(this), CurvePool.withdraw_admin_fees.selector)
        );

        // Make sure CurveAdaptor___NonStandardDecimals() check can handle zero address gauges.
        registry.trustPosition(
            777,
            address(curveAdaptor),
            abi.encode(address(0), EthStethToken, address(0), CurvePool.withdraw_admin_fees.selector)
        );

        // If token and gauge have 18 decimals, then trustPosition should revert in registry.
        decimals = 18;
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(this)))
        );
        registry.trustPosition(
            778,
            address(curveAdaptor),
            abi.encode(address(0), address(this), address(this), CurvePool.withdraw_admin_fees.selector)
        );
    }

    function testRepeatingNativeEthTwiceInInputArray() external {
        // Give the cellar 2 WETH.
        deal(address(WETH), address(cellar), 2e18);

        // ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = ERC20(curveAdaptor.CURVE_ETH());
        tokens[1] = ERC20(curveAdaptor.CURVE_ETH());

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
            EthFrxethPool,
            ERC20(EthFrxethToken),
            amounts,
            0,
            false,
            EthFrxethGauge,
            bytes4(keccak256(abi.encodePacked("price_oracle()")))
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });

        // We expect the call to revert because eventhough the Cellar owns 2 WETH, it has made 2 approvals for 1 WETH each, so
        // the transfer from will fail from not having enough approval.
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        cellar.callOnAdaptor(data);
    }

    function testHelperReentrancyLock() external {
        // Get reentrancy Slot.
        bytes32 reentrancySlot = curveAdaptor.lockedStoragePosition();

        // Set lock slot to 2 to lock it. Then interact with helper while it is "re-entered".
        vm.store(address(curveAdaptor), reentrancySlot, bytes32(uint256(2)));

        ERC20[] memory emptyTokens;
        uint256[] memory amounts;

        vm.expectRevert(bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___Reentrancy.selector)));
        curveAdaptor.addLiquidityETHViaProxy(address(0), ERC20(address(0)), emptyTokens, amounts, 0, false);

        vm.expectRevert(bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___Reentrancy.selector)));
        curveAdaptor.removeLiquidityETHViaProxy(address(0), ERC20(address(0)), 0, emptyTokens, amounts, false);
    }

    function testCellarWithoutOracleTryingToUseCurvePosition() external {
        // Deploy new Cellar.
        string memory cellarName = "Curve Cellar V0.1";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(cellarAddress, initialDeposit);

        bytes memory creationCode = type(Cellar).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );
        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        uint256 assets = 1_000e6;
        deal(address(USDC), address(this), 3 * assets);
        USDC.approve(address(cellar), 3 * assets);
        cellar.deposit(assets, address(this));

        cellar.addPositionToCatalogue(UsdcCrvUsdPoolPosition);
        cellar.addAdaptorToCatalogue(address(curveAdaptor));

        // Scenario 1 (the most likely scenario) strategist adds the position, and rebalances in a single call.

        // Strategist tries to add the curve position.
        bytes[] memory strategistData = new bytes[](2);
        strategistData[0] = abi.encodeWithSelector(
            Cellar.addPosition.selector,
            0,
            UsdcCrvUsdPoolPosition,
            abi.encode(false),
            false
        );

        ERC20 coins0 = ERC20(CurvePool(UsdcCrvUsdPool).coins(0));
        ERC20 coins1 = ERC20(CurvePool(UsdcCrvUsdPool).coins(1));

        // ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = coins0;
        tokens[1] = coins1;

        // uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(
                UsdcCrvUsdPool,
                ERC20(UsdcCrvUsdToken),
                orderedTokenAmounts,
                0,
                UsdcCrvUsdGauge,
                CurvePool.withdraw_admin_fees.selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            strategistData[1] = abi.encodeWithSelector(Cellar.callOnAdaptor.selector, data);
        }

        vm.expectRevert(bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___CallerDoesNotUseOracle.selector)));
        cellar.multicall(strategistData);

        // Scenario 2 (very unlikely but could happen) strategist adds the postiion in a single call.
        cellar.addPosition(0, UsdcCrvUsdPoolPosition, abi.encode(false), false);

        // Cellar totalAssets still works, and position can be removed.
        cellar.totalAssets();
        cellar.deposit(assets, address(this));

        cellar.removePosition(0, false);

        // But if position is added
        cellar.addPosition(0, UsdcCrvUsdPoolPosition, abi.encode(false), false);

        // and an attacker sends LP to the Cellar
        deal(UsdcCrvUsdToken, address(cellar), 1);

        // the Cellar is bricked
        vm.expectRevert(bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___CallerDoesNotUseOracle.selector)));
        cellar.totalAssets();

        vm.expectRevert(bytes(abi.encodeWithSelector(CurveHelper.CurveHelper___CallerDoesNotUseOracle.selector)));
        cellar.deposit(assets, address(this));

        // until forcePositionOut is called
        registry.distrustPosition(UsdcCrvUsdPoolPosition);
        cellar.forcePositionOut(0, UsdcCrvUsdPoolPosition, false);

        // Now cellar is unbricked.
        cellar.totalAssets();
        cellar.deposit(assets, address(this));
    }

    // ========================================= Attacker Tests =========================================

    function testMaliciousStrategistUsingWrongCoinsArray() external {
        // Make a large deposit into Cellar, so we dont trip rebalance deviation.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        uint256 startingUsdcBalance = USDC.balanceOf(address(cellar));

        // Simulate Cellar adding 100 USDC worth of value to ETH FRXETH Pool.
        uint256 valueInLp = priceRouter.getValue(USDC, 100e6, ERC20(EthFrxethToken));
        deal(address(USDC), address(cellar), startingUsdcBalance - 100e6);
        deal(EthFrxethToken, address(cellar), valueInLp);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        uint256[] memory orderedTokenAmountsOut = new uint256[](2);

        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRemoveETHLiquidityFromCurve(
            EthFrxethPool,
            ERC20(EthFrxethToken),
            valueInLp,
            orderedTokenAmountsOut,
            false,
            EthFrxethGauge,
            bytes4(keccak256(abi.encodePacked("price_oracle()")))
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });

        // A normal liquidity redemption would give about $33 ETH and $66 FRXETH.

        // Strategist rebalances but sandwiches their TXs around it.
        cellar.callOnAdaptor(data);

        // No FRXETH should have been left behind in the adaptor.
        uint256 frxEthInAdaptor = FRXETH.balanceOf(address(curveAdaptor));
        assertEq(frxEthInAdaptor, 0, "Curve Adaptor should have no FRXETH in it.");
    }

    // ========================================= Helpers =========================================

    // NOTE Some curve pools use 2 to indicate locked, and 3 to indicate unlocked, others use 1, and 0 respectively
    // But ones that use 1 or 0, are just checking if the slot is truthy or not, so setting it to 2 should still trigger re-entrancy reverts.
    function _verifyReentrancyProtectionWorks(
        address poolAddress,
        address lpToken,
        uint32 position,
        uint256 assets,
        bytes memory expectedRevert
    ) internal {
        // Create a cellar that uses the curve token as the asset.
        cellar = _createCellarWithCurveLPAsAsset(position, lpToken);

        deal(lpToken, address(this), assets);
        ERC20(lpToken).safeApprove(address(cellar), assets);

        CurvePool pool = CurvePool(poolAddress);
        bytes32 slot0 = bytes32(uint256(0));

        // Get the original slot value;
        bytes32 originalValue = vm.load(address(pool), slot0);

        // Set lock slot to 2 to lock it. Then try to deposit while pool is "re-entered".
        vm.store(address(pool), slot0, bytes32(uint256(2)));

        if (expectedRevert.length > 0) {
            vm.expectRevert(expectedRevert);
        } else {
            vm.expectRevert();
        }
        cellar.deposit(assets, address(this));

        // Change lock back to unlocked state
        vm.store(address(pool), slot0, originalValue);

        // Deposit should work now.
        cellar.deposit(assets, address(this));

        // Set lock slot to 2 to lock it. Then try to withdraw while pool is "re-entered".
        vm.store(address(pool), slot0, bytes32(uint256(2)));
        if (expectedRevert.length > 0) {
            vm.expectRevert(expectedRevert);
        } else {
            vm.expectRevert();
        }
        cellar.withdraw(assets / 2, address(this), address(this));

        // Change lock back to unlocked state
        vm.store(address(pool), slot0, originalValue);

        // Withdraw should work now.
        cellar.withdraw(assets / 2, address(this), address(this));
    }

    function _createCellarWithCurveLPAsAsset(uint32 position, address lpToken) internal returns (Cellar newCellar) {
        string memory cellarName = "Test Curve Cellar V0.0";
        uint256 initialDeposit = 1e6;
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

        newCellar.addAdaptorToCatalogue(address(curveAdaptor));
    }

    function _curveLPAsAccountingAsset(uint256 assets, ERC20 token, uint32 positionId, address gauge) internal {
        string memory cellarName = "Curve LP Cellar V0.0";
        // Approve new cellar to spend assets.
        initialAssets = 1e18;
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(token), address(this), initialAssets);
        token.approve(cellarAddress, initialAssets);

        bytes memory creationCode = type(MockCellarWithOracle).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(this),
            registry,
            token,
            cellarName,
            cellarName,
            positionId,
            abi.encode(true),
            initialAssets,
            0.75e18,
            type(uint192).max
        );
        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));
        cellar.addAdaptorToCatalogue(address(curveAdaptor));
        cellar.setRebalanceDeviation(0.030e18);

        token.safeApprove(address(cellar), assets);
        deal(address(token), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 balanceInGauge = CurveGauge(gauge).balanceOf(address(cellar));
        assertEq(assets + initialAssets, balanceInGauge, "Should have deposited assets into gauge.");

        // Strategist rebalances to pull half of assets from gauge.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, balanceInGauge / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        // Make sure when we redeem we pull from gauge and cellar wallet.
        uint256 sharesToRedeem = cellar.balanceOf(address(this));
        cellar.redeem(sharesToRedeem, address(this), address(this));

        assertEq(token.balanceOf(address(this)), assets);
    }

    function _manageLiquidityIn2PoolNoETH(
        uint256 assets,
        address pool,
        address token,
        address gauge,
        uint256 tolerance,
        bytes4 selector
    ) internal {
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        ERC20 coins0 = ERC20(CurvePool(pool).coins(0));
        ERC20 coins1 = ERC20(CurvePool(pool).coins(1));

        // Convert cellars USDC balance into coins0.
        if (coins0 != USDC) {
            if (address(coins0) == curveAdaptor.CURVE_ETH()) {
                assets = priceRouter.getValue(USDC, assets, WETH);
                deal(address(WETH), address(cellar), assets);
            } else {
                assets = priceRouter.getValue(USDC, assets, coins0);
                if (coins0 == STETH) _takeSteth(assets, address(cellar));
                else if (coins0 == OETH) _takeOeth(assets, address(cellar));
                else deal(address(coins0), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), 0);
        }

        // ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = coins0;
        tokens[1] = coins1;

        // uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets / 2;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(
                pool,
                ERC20(token),
                orderedTokenAmounts,
                0,
                gauge,
                selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        uint256 cellarCurveLPBalance = ERC20(token).balanceOf(address(cellar));

        expectedValueOut = priceRouter.getValue(coins0, assets / 2, ERC20(token));
        assertApproxEqRel(
            cellarCurveLPBalance,
            expectedValueOut,
            tolerance,
            "Cellar should have received expected value out."
        );

        // Strategist rebalances into LP , dual asset.
        // Simulate a swap by minting Cellar CRVUSD in exchange for USDC.
        {
            uint256 coins1Amount = priceRouter.getValue(coins0, assets / 4, coins1);
            orderedTokenAmounts[0] = assets / 4;
            orderedTokenAmounts[1] = coins1Amount;
            if (coins0 == STETH) _takeSteth(assets / 4, address(cellar));
            else if (coins0 == OETH) _takeOeth(assets / 4, address(cellar));
            else deal(address(coins0), address(cellar), assets / 4);
            if (coins1 == STETH) _takeSteth(coins1Amount, address(cellar));
            else if (coins1 == OETH) _takeOeth(coins1Amount, address(cellar));
            else deal(address(coins1), address(cellar), coins1Amount);
        }
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(
                pool,
                ERC20(token),
                orderedTokenAmounts,
                0,
                gauge,
                selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertGt(ERC20(token).balanceOf(address(cellar)), 0, "Should have added liquidity");

        expectedValueOut = priceRouter.getValues(tokens, orderedTokenAmounts, ERC20(token));
        uint256 actualValueOut = ERC20(token).balanceOf(address(cellar)) - cellarCurveLPBalance;

        assertApproxEqRel(
            actualValueOut,
            expectedValueOut,
            tolerance,
            "Cellar should have received expected value out."
        );

        // uint256[] memory balanceDelta = new uint256[](2);
        balanceDelta[0] = coins0.balanceOf(address(cellar));
        balanceDelta[1] = coins1.balanceOf(address(cellar));

        // Strategist stakes LP.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            uint256 expectedLPStaked = ERC20(token).balanceOf(address(cellar));

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToStakeCurveLP(token, gauge, type(uint256).max, pool, selector);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);

            assertEq(CurveGauge(gauge).balanceOf(address(cellar)), expectedLPStaked, "Should have staked LP in gauge.");
        }
        // Pass time.
        _skip(1 days);

        // Strategist unstakes half the LP.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            uint256 lpStaked = CurveGauge(gauge).balanceOf(address(cellar));

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, lpStaked / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);

            assertApproxEqAbs(
                CurveGauge(gauge).balanceOf(address(cellar)),
                lpStaked / 2,
                1,
                "Should have staked LP in gauge."
            );
        }

        // Zero out cellars LP balance.
        deal(address(CRV), address(cellar), 0);

        // Pass time.
        _skip(1 days);

        // Unstake remaining LP, and call getRewards.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](2);
            adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, type(uint256).max);
            adaptorCalls[1] = _createBytesDataToClaimRewardsForCurveLP(gauge);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        // TODO assertGt(CRV.balanceOf(address(cellar)), 0, "Cellar should have recieved CRV rewards.");

        // Strategist pulls liquidity dual asset.
        // orderedTokenAmounts = new uint256[](2); // Specify zero for min amounts out.
        uint256 amountToPull = ERC20(token).balanceOf(address(cellar));
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRemoveLiquidityFromCurve(
                pool,
                ERC20(token),
                amountToPull,
                new uint256[](2),
                gauge,
                selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        balanceDelta[0] = coins0.balanceOf(address(cellar)) - balanceDelta[0];
        balanceDelta[1] = coins1.balanceOf(address(cellar)) - balanceDelta[1];

        actualValueOut = priceRouter.getValues(tokens, balanceDelta, ERC20(token));
        assertApproxEqRel(actualValueOut, amountToPull, tolerance, "Cellar should have received expected value out.");

        assertTrue(ERC20(token).balanceOf(address(cellar)) == 0, "Should have redeemed all of cellars Curve LP Token.");
    }

    function _manageLiquidityIn2PoolWithETH(
        uint256 assets,
        address pool,
        address token,
        address gauge,
        uint256 tolerance,
        bytes4 selector
    ) internal {
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // ERC20[] memory coins = new ERC20[](2);
        coins[0] = ERC20(CurvePool(pool).coins(0));
        coins[1] = ERC20(CurvePool(pool).coins(1));

        // Convert cellars USDC balance into coins0.
        if (coins[0] != USDC) {
            if (address(coins[0]) == curveAdaptor.CURVE_ETH()) {
                assets = priceRouter.getValue(USDC, assets, WETH);
                deal(address(WETH), address(cellar), assets);
            } else {
                assets = priceRouter.getValue(USDC, assets, coins[0]);
                if (coins[0] == STETH) _takeSteth(assets, address(cellar));
                else if (coins[0] == OETH) _takeOeth(assets, address(cellar));
                else deal(address(coins[0]), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), 0);
        }

        // ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = coins[0];
        tokens[1] = coins[1];

        if (address(coins[0]) == curveAdaptor.CURVE_ETH()) coins[0] = WETH;
        if (address(coins[1]) == curveAdaptor.CURVE_ETH()) coins[1] = WETH;

        // uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets / 2;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
                pool,
                ERC20(token),
                orderedTokenAmounts,
                0,
                false,
                gauge,
                selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        uint256 cellarCurveLPBalance = ERC20(token).balanceOf(address(cellar));

        expectedValueOut = priceRouter.getValue(coins[0], assets / 2, ERC20(token));
        assertApproxEqRel(
            cellarCurveLPBalance,
            expectedValueOut,
            tolerance,
            "Cellar should have received expected value out."
        );

        // Strategist rebalances into LP , dual asset.
        // Simulate a swap by minting Cellar CRVUSD in exchange for USDC.
        {
            uint256 coins1Amount = priceRouter.getValue(coins[0], assets / 4, coins[1]);
            orderedTokenAmounts[0] = assets / 4;
            orderedTokenAmounts[1] = coins1Amount;
            if (coins[0] == STETH) _takeSteth(assets / 4, address(cellar));
            else if (coins[0] == OETH) _takeOeth(assets / 4, address(cellar));
            else deal(address(coins[0]), address(cellar), assets / 4);
            if (coins[1] == STETH) _takeSteth(coins1Amount, address(cellar));
            else if (coins[1] == OETH) _takeOeth(coins1Amount, address(cellar));
            else deal(address(coins[1]), address(cellar), coins1Amount);
        }
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
                pool,
                ERC20(token),
                orderedTokenAmounts,
                0,
                false,
                gauge,
                selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertGt(ERC20(token).balanceOf(address(cellar)), 0, "Should have added liquidity");

        {
            uint256 actualValueOut = ERC20(token).balanceOf(address(cellar)) - cellarCurveLPBalance;
            expectedValueOut = priceRouter.getValues(coins, orderedTokenAmounts, ERC20(token));

            assertApproxEqRel(
                actualValueOut,
                expectedValueOut,
                tolerance,
                "Cellar should have received expected value out."
            );
        }

        // uint256[] memory balanceDelta = new uint256[](2);
        balanceDelta[0] = coins[0].balanceOf(address(cellar));
        balanceDelta[1] = coins[1].balanceOf(address(cellar));

        // Strategist stakes LP.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            uint256 expectedLPStaked = ERC20(token).balanceOf(address(cellar));

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToStakeCurveLP(token, gauge, type(uint256).max, pool, selector);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);

            assertEq(CurveGauge(gauge).balanceOf(address(cellar)), expectedLPStaked, "Should have staked LP in gauge.");
        }
        // Pass time.
        _skip(1 days);

        // Strategist unstakes half the LP, claiming rewards.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            uint256 lpStaked = CurveGauge(gauge).balanceOf(address(cellar));

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, lpStaked / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);

            assertApproxEqAbs(
                CurveGauge(gauge).balanceOf(address(cellar)),
                lpStaked / 2,
                1,
                "Should have staked LP in gauge."
            );
        }

        // Zero out cellars LP balance.
        deal(address(CRV), address(cellar), 0);

        // Pass time.
        _skip(1 days);

        // Unstake remaining LP, and call getRewards.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](2);
            adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, type(uint256).max);
            adaptorCalls[1] = _createBytesDataToClaimRewardsForCurveLP(gauge);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        // TODO assertGt(CRV.balanceOf(address(cellar)), 0, "Cellar should have recieved CRV rewards.");

        // Strategist pulls liquidity dual asset.
        orderedTokenAmounts = new uint256[](2); // Specify zero for min amounts out.
        uint256 amountToPull = ERC20(token).balanceOf(address(cellar));
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRemoveETHLiquidityFromCurve(
                pool,
                ERC20(token),
                amountToPull,
                orderedTokenAmounts,
                false,
                gauge,
                selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        balanceDelta[0] = coins[0].balanceOf(address(cellar)) - balanceDelta[0];
        balanceDelta[1] = coins[1].balanceOf(address(cellar)) - balanceDelta[1];

        {
            uint256 actualValueOut = priceRouter.getValues(coins, balanceDelta, ERC20(token));
            assertApproxEqRel(
                actualValueOut,
                amountToPull,
                tolerance,
                "Cellar should have received expected value out."
            );
        }

        assertTrue(ERC20(token).balanceOf(address(cellar)) == 0, "Should have redeemed all of cellars Curve LP Token.");
    }

    function _checkForReentrancyOnWithdraw(
        uint256 assets,
        address pool,
        address token,
        address gauge,
        bytes4 selector
    ) internal {
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // ERC20[] memory coins = new ERC20[](2);
        coins[0] = ERC20(CurvePool(pool).coins(0));
        coins[1] = ERC20(CurvePool(pool).coins(1));

        // Convert cellars USDC balance into coins0.
        if (coins[0] != USDC) {
            if (address(coins[0]) == curveAdaptor.CURVE_ETH()) {
                assets = priceRouter.getValue(USDC, assets, WETH);
                deal(address(WETH), address(cellar), assets);
            } else {
                assets = priceRouter.getValue(USDC, assets, coins[0]);
                if (coins[0] == STETH) _takeSteth(assets, address(cellar));
                else if (coins[0] == OETH) _takeOeth(assets, address(cellar));
                else deal(address(coins[0]), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), 0);
        }

        // ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = coins[0];
        tokens[1] = coins[1];

        if (address(coins[0]) == curveAdaptor.CURVE_ETH()) coins[0] = WETH;
        if (address(coins[1]) == curveAdaptor.CURVE_ETH()) coins[1] = WETH;

        // uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
                pool,
                ERC20(token),
                orderedTokenAmounts,
                0,
                false,
                gauge,
                selector
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        // Mint attacker Curve LP so they can withdraw liquidity and re-enter.
        deal(token, address(this), 1e18);

        CurvePool curvePool = CurvePool(pool);

        // Attacker tries en-entering into Cellar on ETH recieve but redeem reverts.
        attackCellar = true;
        vm.expectRevert();
        curvePool.remove_liquidity(1e18, [uint256(0), 0]);

        // But if there is no re-entrancy attackers remove_liquidity calls is successful, and they can redeem.
        attackCellar = false;
        curvePool.remove_liquidity(1e18, [uint256(0), 0]);

        uint256 maxRedeem = cellar.maxRedeem(address(this));
        cellar.redeem(maxRedeem, address(this), address(this));
    }

    receive() external payable {
        if (attackCellar) {
            uint256 maxRedeem = cellar.maxRedeem(address(this));
            cellar.redeem(maxRedeem, address(this), address(this));
        }
    }

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

    function _takeSteth(uint256 amount, address to) internal {
        // STETH does not work with DEAL, so steal STETH from a whale.
        address stethWhale = 0x18709E89BD403F470088aBDAcEbE86CC60dda12e;
        vm.prank(stethWhale);
        STETH.safeTransfer(to, amount);
    }

    function _takeOeth(uint256 amount, address to) internal {
        // STETH does not work with DEAL, so steal STETH from a whale.
        address oethWhale = 0xEADB3840596cabF312F2bC88A4Bb0b93A4E1FF5F;
        vm.prank(oethWhale);
        OETH.safeTransfer(to, amount);
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
        mockSTETdataFeed.setMockUpdatedAt(block.timestamp);
        mockRETHdataFeed.setMockUpdatedAt(block.timestamp);
    }
}
