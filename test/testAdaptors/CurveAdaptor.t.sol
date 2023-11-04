// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { CellarWithOracle } from "src/base/permutations/CellarWithOracle.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CurveEMAExtension } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";
import { CurveAdaptor, CurvePool } from "src/modules/Adaptors/Curve/CurveAdaptor.sol";
import { Curve2PoolExtension } from "src/modules/price-router/Extensions/Curve/Curve2PoolExtension.sol";

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

    uint32 private usdcPosition = 1;
    uint32 private crvusdPosition = 2;
    uint32 private wethPosition = 3;
    uint32 private rethPosition = 4;
    uint32 private usdtPosition = 5;
    uint32 private stethPosition = 6;
    uint32 private fraxPosition = 7;
    uint32 private frxethPosition = 8;
    uint32 private cvxPosition = 9;
    uint32 private UsdcCrvUsdPoolPosition = 10;
    uint32 private WethRethPoolPosition = 11;
    uint32 private UsdtCrvUsdPoolPosition = 12;
    uint32 private EthStethPoolPosition = 13;
    uint32 private FraxUsdcPoolPosition = 14;
    uint32 private WethFrxethPoolPosition = 15;
    uint32 private EthFrxethPoolPosition = 16;
    uint32 private StethFrxethPoolPosition = 17;
    uint32 private WethCvxPoolPosition = 18;

    uint32 private slippage = 0.9e4;
    uint256 public initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18492720;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        curveAdaptor = new CurveAdaptor(address(WETH), slippage);
        curveEMAExtension = new CurveEMAExtension(priceRouter, address(WETH), 18);
        curve2PoolExtension = new Curve2PoolExtension(priceRouter, address(WETH), 18);
        wstethExtension = new WstEthExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        // Add WETH pricing.
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Add USDC pricing.
        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Add DAI pricing.
        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // Add USDT pricing.
        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        // Add FRAX pricing.
        price = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        // Add stETH pricing.
        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        // Add rETH pricing.
        stor.inETH = true;
        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
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
        price = curveEMAExtension.getPriceFromCurvePool(CurvePool(cStor.pool), cStor.index, cStor.needIndex);
        price = price.mulDivDown(priceRouter.getPriceInUSD(USDC), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(CRVUSD, settings, abi.encode(cStor), price);

        // Add FrxEth
        cStor.pool = WethFrxethPool;
        cStor.index = 0;
        cStor.needIndex = false;
        price = curveEMAExtension.getPriceFromCurvePool(CurvePool(cStor.pool), cStor.index, cStor.needIndex);
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(FRXETH, settings, abi.encode(cStor), price);

        // Add CVX
        cStor.pool = WethCvxPool;
        cStor.index = 0;
        cStor.needIndex = false;
        price = curveEMAExtension.getPriceFromCurvePool(CurvePool(cStor.pool), cStor.index, cStor.needIndex);
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(curveEMAExtension));
        priceRouter.addAsset(CVX, settings, abi.encode(cStor), price);

        // Add 2pools.
        // UsdcCrvUsdPool
        // UsdcCrvUsdToken
        // UsdcCrvUsdGauge
        _add2PoolAssetToPriceRouter(UsdcCrvUsdPool, UsdcCrvUsdToken, true, 1e8);
        // WethRethPool
        // WethRethToken
        // WethRethGauge
        _add2PoolAssetToPriceRouter(WethRethPool, WethRethToken, false, 3_863e8);
        // UsdtCrvUsdPool
        // UsdtCrvUsdToken
        // UsdtCrvUsdGauge
        _add2PoolAssetToPriceRouter(UsdtCrvUsdPool, UsdtCrvUsdToken, true, 1e8);
        // EthStethPool
        // EthStethToken
        // EthStethGauge
        _add2PoolAssetToPriceRouter(EthStethPool, EthStethToken, true, 1956e8);
        // FraxUsdcPool
        // FraxUsdcToken
        // FraxUsdcGauge
        _add2PoolAssetToPriceRouter(FraxUsdcPool, FraxUsdcToken, true, 1e8);
        // WethFrxethPool
        // WethFrxethToken
        // WethFrxethGauge
        _add2PoolAssetToPriceRouter(WethFrxethPool, WethFrxethToken, true, 1800e8);
        // EthFrxethPool
        // EthFrxethToken
        // EthFrxethGauge
        _add2PoolAssetToPriceRouter(EthFrxethPool, EthFrxethToken, true, 1800e8);
        // StethFrxethPool
        // StethFrxethToken
        // StethFrxethGauge
        _add2PoolAssetToPriceRouter(StethFrxethPool, StethFrxethToken, true, 1825e8);
        // WethCvxPool
        // WethCvxToken
        // WethCvxGauge
        _add2PoolAssetToPriceRouter(WethCvxPool, WethCvxToken, false, 154e8);

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
        registry.trustPosition(
            UsdtCrvUsdPoolPosition,
            address(curveAdaptor),
            abi.encode(UsdtCrvUsdPool, UsdtCrvUsdToken, UsdtCrvUsdGauge, CurvePool.withdraw_admin_fees.selector)
        );
        registry.trustPosition(
            EthStethPoolPosition,
            address(curveAdaptor),
            abi.encode(EthStethPool, EthStethToken, EthStethGauge, CurvePool.withdraw_admin_fees.selector)
        );
        registry.trustPosition(
            FraxUsdcPoolPosition,
            address(curveAdaptor),
            abi.encode(FraxUsdcPool, FraxUsdcToken, FraxUsdcGauge, CurvePool.withdraw_admin_fees.selector)
        );
        registry.trustPosition(
            WethFrxethPoolPosition,
            address(curveAdaptor),
            abi.encode(WethFrxethPool, WethFrxethToken, WethFrxethGauge, CurvePool.withdraw_admin_fees.selector)
        );
        registry.trustPosition(
            EthFrxethPoolPosition,
            address(curveAdaptor),
            abi.encode(EthFrxethPool, EthFrxethToken, EthFrxethGauge, CurvePool.withdraw_admin_fees.selector)
        );
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

        string memory cellarName = "Curve Cellar V0.0";
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
            abi.encode(0),
            initialDeposit,
            platformCut,
            type(uint192).max
        );
        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(curveAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        for (uint32 i = 2; i < 19; ++i) cellar.addPositionToCatalogue(i);
        for (uint32 i = 2; i < 19; ++i) cellar.addPosition(0, i, abi.encode(false), false);

        cellar.setRebalanceDeviation(0.030e18);

        initialAssets = cellar.totalAssets();
    }

    // ========================================= HAPPY PATH TESTS =========================================

    function testManagingLiquidityIn2PoolNoETH0(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _manageLiquidityIn2PoolNoETH(assets, UsdcCrvUsdPool, UsdcCrvUsdToken, 0.0005e18);
    }

    function testManagingLiquidityIn2PoolNoETH1(uint256 assets) external {
        // Pool only has 6M TVL so it experiences very high slippage.
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(assets, WethRethPool, WethRethToken, 0.0005e18);
    }

    function testManagingLiquidityIn2PoolNoETH2(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(assets, UsdtCrvUsdPool, UsdtCrvUsdToken, 0.0005e18);
    }

    function testManagingLiquidityIn2PoolNoETH3(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(assets, FraxUsdcPool, FraxUsdcToken, 0.0005e18);
    }

    function testManagingLiquidityIn2PoolNoETH4(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(assets, WethFrxethPool, WethFrxethToken, 0.0005e18);
    }

    function testManagingLiquidityIn2PoolNoETH5(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(assets, StethFrxethPool, StethFrxethToken, 0.0010e18);
    }

    function testManagingLiquidityIn2PoolNoETH6(uint256 assets) external {
        // Pool has a very high fee.
        assets = bound(assets, 1e6, 100_000e6);
        _manageLiquidityIn2PoolNoETH(assets, WethCvxPool, WethCvxToken, 0.0050e18);
    }

    function testManagingLiquidityIn2PoolCorrelatedWithETH0(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _manageLiquidityIn2PoolWithETH(assets, EthStethPool, EthStethToken, 0.0030e18);
    }

    function testManagingLiquidityIn2PoolCorrelatedWithETH1(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        _manageLiquidityIn2PoolWithETH(assets, EthFrxethPool, EthFrxethToken, 0.0010e18);
    }

    // TODO for sDAI and sFRAX pools, I think that they are a special pool type, where there is no LP price,
    // so in pricing we need to either use the price of the underlying, or take the sDAI price, and divide out the rate.

    // ========================================= Reverts =========================================
    // ========================================= Helpers =========================================
    function _manageLiquidityIn2PoolNoETH(uint256 assets, address pool, address token, uint256 tolerance) internal {
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        CurvePool curvePool = CurvePool(pool);
        ERC20 coins0 = ERC20(curvePool.coins(0));
        ERC20 coins1 = ERC20(curvePool.coins(1));

        // Convert cellars USDC balance into coins0.
        if (coins0 != USDC) {
            if (address(coins0) == curveAdaptor.CURVE_ETH()) {
                assets = priceRouter.getValue(USDC, assets, WETH);
                deal(address(WETH), address(cellar), assets);
            } else {
                assets = priceRouter.getValue(USDC, assets, coins0);
                if (coins0 == STETH) _takeSteth(assets, address(cellar));
                else deal(address(coins0), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), 0);
        }

        ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = coins0;
        tokens[1] = coins1;

        uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets / 2;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(pool, ERC20(token), tokens, orderedTokenAmounts, 0);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        uint256 cellarCurveLPBalance = ERC20(token).balanceOf(address(cellar));

        uint256 expectedValueOut = priceRouter.getValue(coins0, assets / 2, ERC20(token));
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
            else deal(address(coins0), address(cellar), assets / 4);
            if (coins1 == STETH) _takeSteth(coins1Amount, address(cellar));
            else deal(address(coins1), address(cellar), coins1Amount);
        }
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(pool, ERC20(token), tokens, orderedTokenAmounts, 0);
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

        uint256[] memory balanceDelta = new uint256[](2);
        balanceDelta[0] = coins0.balanceOf(address(cellar));
        balanceDelta[1] = coins1.balanceOf(address(cellar));

        // Strategist pulls liquidity dual asset.
        orderedTokenAmounts = new uint256[](2); // Specify zero for min amounts out.
        uint256 amountToPull = ERC20(token).balanceOf(address(cellar));
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRemoveLiquidityFromCurve(
                pool,
                ERC20(token),
                amountToPull,
                tokens,
                orderedTokenAmounts
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

    function _manageLiquidityIn2PoolWithETH(uint256 assets, address pool, address token, uint256 tolerance) internal {
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
                else deal(address(coins0), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), 0);
        }

        ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = coins0;
        tokens[1] = coins1;

        if (address(coins0) == curveAdaptor.CURVE_ETH()) coins0 = WETH;
        if (address(coins1) == curveAdaptor.CURVE_ETH()) coins1 = WETH;

        uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets / 2;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
                pool,
                ERC20(token),
                tokens,
                orderedTokenAmounts,
                0,
                false
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        uint256 cellarCurveLPBalance = ERC20(token).balanceOf(address(cellar));

        uint256 expectedValueOut = priceRouter.getValue(coins0, assets / 2, ERC20(token));
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
            else deal(address(coins0), address(cellar), assets / 4);
            if (coins1 == STETH) _takeSteth(coins1Amount, address(cellar));
            else deal(address(coins1), address(cellar), coins1Amount);
        }
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
                pool,
                ERC20(token),
                tokens,
                orderedTokenAmounts,
                0,
                false
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertGt(ERC20(token).balanceOf(address(cellar)), 0, "Should have added liquidity");

        uint256 actualValueOut = ERC20(token).balanceOf(address(cellar)) - cellarCurveLPBalance;
        {
            ERC20[] memory coins = new ERC20[](2);
            coins[0] = coins0;
            coins[1] = coins1;
            expectedValueOut = priceRouter.getValues(coins, orderedTokenAmounts, ERC20(token));

            assertApproxEqRel(
                actualValueOut,
                expectedValueOut,
                tolerance,
                "Cellar should have received expected value out."
            );
        }

        uint256[] memory balanceDelta = new uint256[](2);
        balanceDelta[0] = coins0.balanceOf(address(cellar));
        balanceDelta[1] = coins1.balanceOf(address(cellar));

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
                tokens,
                orderedTokenAmounts,
                false
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        balanceDelta[0] = coins0.balanceOf(address(cellar)) - balanceDelta[0];
        balanceDelta[1] = coins1.balanceOf(address(cellar)) - balanceDelta[1];

        {
            ERC20[] memory coins = new ERC20[](2);
            coins[0] = coins0;
            coins[1] = coins1;
            actualValueOut = priceRouter.getValues(coins, balanceDelta, ERC20(token));
            assertApproxEqRel(
                actualValueOut,
                amountToPull,
                tolerance,
                "Cellar should have received expected value out."
            );
        }

        assertTrue(ERC20(token).balanceOf(address(cellar)) == 0, "Should have redeemed all of cellars Curve LP Token.");
    }

    function _add2PoolAssetToPriceRouter(
        address pool,
        address token,
        bool isCorrelated,
        uint256 expectedPrice
    ) internal {
        Curve2PoolExtension.ExtensionStorage memory stor;
        stor.pool = pool;
        stor.isCorrelated = isCorrelated;
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
}
