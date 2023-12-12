// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Curve2PoolExtension, Extension } from "src/modules/price-router/Extensions/Curve/Curve2PoolExtension.sol";
import { CurveEMAExtension } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";
import { ERC4626Extension } from "src/modules/price-router/Extensions/ERC4626Extension.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { CurvePool } from "src/interfaces/external/Curve/CurvePool.sol";
import { CurvePoolETH } from "src/interfaces/external/Curve/CurvePoolETH.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract PricingCurveLpTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;

    // Deploy the extension.
    Curve2PoolExtension private curve2PoolExtension;
    CurveEMAExtension private curveEMAExtension;
    ERC4626Extension private erc4626Extension;

    struct PricingData {
        address pool;
        address lpToken;
        bytes4 reentrancySelector;
        bool indexIsUint256OrInt128;
        uint256 attackValueInUSDC;
        uint256 lockedState;
    }

    PricingData[] public pricingData;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18714544;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        curve2PoolExtension = new Curve2PoolExtension(priceRouter, address(WETH), 18);
        curveEMAExtension = new CurveEMAExtension(priceRouter, address(WETH), 18);
        erc4626Extension = new ERC4626Extension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CRVUSD_USD_FEED);
        priceRouter.addAsset(CRVUSD, settings, abi.encode(stor), 1e8);

        uint256 price;

        // Nonstable coins.
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(CVX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CVX_USD_FEED);
        priceRouter.addAsset(CVX, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        // Add ETH based feeds
        stor.inETH = true;
        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        ERC4626 sDaiVault = ERC4626(savingsDaiAddress);
        ERC20 sDAI = ERC20(savingsDaiAddress);
        uint256 oneSDaiShare = 10 ** sDaiVault.decimals();
        uint256 sDaiShareInDai = sDaiVault.previewRedeem(oneSDaiShare);
        price = priceRouter.getPriceInUSD(DAI).mulDivDown(sDaiShareInDai, 10 ** DAI.decimals());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(erc4626Extension));
        priceRouter.addAsset(sDAI, settings, abi.encode(0), price);

        ERC4626 sFraxVault = ERC4626(sFRAX);
        ERC20 sFRAX = ERC20(sFRAX);
        uint256 oneSFRAXShare = 10 ** sFraxVault.decimals();
        uint256 sFRAXShareInFrax = sFraxVault.previewRedeem(oneSFRAXShare);
        price = priceRouter.getPriceInUSD(FRAX).mulDivDown(sFRAXShareInFrax, 10 ** DAI.decimals());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(erc4626Extension));
        priceRouter.addAsset(sFRAX, settings, abi.encode(0), price);

        // Add FRXETH using EMA Externsion.
        CurveEMAExtension.ExtensionStorage memory cStor;
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

        // Add in 2pool assets.
        _add2PoolAssetToPriceRouter(UsdcCrvUsdPool, UsdcCrvUsdToken, USDC, CRVUSD, false, false, 0, 10e4);
        _add2PoolAssetToPriceRouter(WethCvxPool, WethCvxToken, WETH, CVX, false, false, 0, 10e4);
        _add2PoolAssetToPriceRouter(EthStethPool, EthStethToken, WETH, STETH, false, false, .95e4, 1.1e4);
        _add2PoolAssetToPriceRouter(UsdtCrvUsdPool, UsdtCrvUsdToken, USDT, CRVUSD, false, false, 0, 10e4);
        _add2PoolAssetToPriceRouter(EthStethNgPool, EthStethNgToken, WETH, STETH, false, false, 0, 10e4);
        _add2PoolAssetToPriceRouter(FraxCrvUsdPool, FraxCrvUsdToken, FRAX, CRVUSD, false, false, 0, 10e4);
        _add2PoolAssetToPriceRouter(CrvUsdSdaiPool, CrvUsdSdaiToken, CRVUSD, sDAI, false, true, 0, 10e4); // Since we are using sDAI as the underlying, the second bool must be true so we account for rate.
        _add2PoolAssetToPriceRouter(CrvUsdSfraxPool, CrvUsdSfraxToken, CRVUSD, FRAX, false, false, 0, 10e4); // Since we are using FRAX as the underlying, the second bool should be false.
        _add2PoolAssetToPriceRouter(EthFrxethPool, EthFrxethToken, WETH, FRXETH, false, false, 0, 10e4);
        _add2PoolAssetToPriceRouter(StethFrxethPool, StethFrxethToken, STETH, FRXETH, false, false, 0, 10e4);

        pricingData.push(
            PricingData({
                pool: UsdcCrvUsdPool,
                lpToken: UsdcCrvUsdToken,
                reentrancySelector: bytes4(0),
                indexIsUint256OrInt128: false,
                attackValueInUSDC: 1_000_000_000e6,
                lockedState: 2
            })
        );

        pricingData.push(
            PricingData({
                pool: WethCvxPool,
                lpToken: WethCvxToken,
                reentrancySelector: bytes4(keccak256(abi.encodePacked("claim_admin_fees()"))),
                indexIsUint256OrInt128: true,
                attackValueInUSDC: 500_000_000e6,
                lockedState: 2
            })
        );

        pricingData.push(
            PricingData({
                pool: EthStethPool,
                lpToken: EthStethToken,
                reentrancySelector: bytes4(0),
                indexIsUint256OrInt128: false,
                attackValueInUSDC: 100_000_000e6,
                lockedState: 2
            })
        );

        pricingData.push(
            PricingData({
                pool: UsdtCrvUsdPool,
                lpToken: UsdtCrvUsdToken,
                reentrancySelector: bytes4(0),
                indexIsUint256OrInt128: false,
                attackValueInUSDC: 500_000_000e6,
                lockedState: 2
            })
        );

        pricingData.push(
            PricingData({
                pool: EthStethNgPool,
                lpToken: EthStethNgToken,
                reentrancySelector: bytes4(keccak256(abi.encodePacked("get_virtual_price()"))),
                indexIsUint256OrInt128: false,
                attackValueInUSDC: 500_000_000e6,
                lockedState: 2
            })
        );

        pricingData.push(
            PricingData({
                pool: FraxCrvUsdPool,
                lpToken: FraxCrvUsdToken,
                reentrancySelector: bytes4(0),
                indexIsUint256OrInt128: false,
                attackValueInUSDC: 500_000_000e6,
                lockedState: 2
            })
        );

        pricingData.push(
            PricingData({
                pool: CrvUsdSdaiPool,
                lpToken: CrvUsdSdaiToken,
                reentrancySelector: bytes4(keccak256(abi.encodePacked("get_virtual_price()"))),
                indexIsUint256OrInt128: false,
                attackValueInUSDC: 100_000_000e6,
                lockedState: 1
            })
        );

        pricingData.push(
            PricingData({
                pool: CrvUsdSfraxPool,
                lpToken: CrvUsdSfraxToken,
                reentrancySelector: bytes4(keccak256(abi.encodePacked("get_virtual_price()"))),
                indexIsUint256OrInt128: false,
                attackValueInUSDC: 300_000_000e6,
                lockedState: 1
            })
        );

        pricingData.push(
            PricingData({
                pool: EthFrxethPool,
                lpToken: EthFrxethToken,
                reentrancySelector: bytes4(keccak256(abi.encodePacked("price_oracle()"))),
                indexIsUint256OrInt128: false,
                attackValueInUSDC: 1_000_000_000e6,
                lockedState: 2
            })
        );

        pricingData.push(
            PricingData({
                pool: StethFrxethPool,
                lpToken: StethFrxethToken,
                reentrancySelector: bytes4(0),
                indexIsUint256OrInt128: false,
                attackValueInUSDC: 100_000_000e6,
                lockedState: 2
            })
        );
    }

    function testPricingCurveLp() external {
        for (uint256 i; i < pricingData.length; ++i) {
            uint256 snapshot = vm.snapshot();
            // Make sure Reentrancy function does in fact check for reentrancy
            _callReentrancyFunction(pricingData[i].pool, pricingData[i].reentrancySelector, pricingData[i].lockedState);

            // Try manipulating a pools lp price
            _attackPool(pricingData[i].pool, pricingData[i].indexIsUint256OrInt128, pricingData[i].attackValueInUSDC);
            uint256 expectedLPPrice = _getLpPriceUsingRemoveLiquidity(
                CurvePool(pricingData[i].pool),
                ERC20(pricingData[i].lpToken)
            );
            uint256 actualLPPrice = priceRouter.getPriceInUSD(ERC20(pricingData[i].lpToken));
            assertApproxEqRel(
                actualLPPrice,
                expectedLPPrice,
                0.01e18,
                "Actual should approximately equal expected LP price."
            );
            vm.revertTo(snapshot);
        }
    }

    function _callReentrancyFunction(address poolAddress, bytes4 selector, uint256 lockedState) internal {
        if (selector == bytes4(0)) return;

        bool success;

        CurvePool pool = CurvePool(poolAddress);
        bytes32 slot0 = bytes32(uint256(0));

        // Get the original slot value;
        bytes32 originalValue = vm.load(address(pool), slot0);

        // Set lock slot to 2 to lock it. Then try to deposit while pool is "re-entered".
        vm.store(address(pool), slot0, bytes32(uint256(lockedState)));

        (success, ) = address(pool).call(abi.encodePacked(selector));

        assertTrue(success == false, "Call should have failed.");

        // Change lock back to unlocked state
        vm.store(address(pool), slot0, originalValue);

        (success, ) = address(pool).call(abi.encodePacked(selector));
        assertTrue(success == true, "Call should have succeed.");
    }

    function _attackPool(address pool, bool indexIsUint256OrInt128, uint256 attackValueInUSDC) internal {
        ERC20[] memory coins = new ERC20[](2);
        coins[0] = ERC20(CurvePool(pool).coins(0));
        coins[1] = ERC20(CurvePool(pool).coins(1));

        // Make a very large swap.
        uint256 amountToSwap = priceRouter.getValue(
            USDC,
            attackValueInUSDC,
            address(coins[0]) == ETH ? WETH : coins[0]
        );
        uint256 largeSwapOut;
        _deal(address(coins[0]), address(this), amountToSwap);
        if (address(coins[0]) == ETH) {
            largeSwapOut = indexIsUint256OrInt128
                ? cp0Eth(pool).exchange{ value: amountToSwap }(0, 1, amountToSwap, 0)
                : cp1Eth(pool).exchange{ value: amountToSwap }(0, 1, amountToSwap, 0);
        } else {
            coins[0].safeApprove(pool, amountToSwap);
            largeSwapOut = indexIsUint256OrInt128
                ? cp0(pool).exchange(0, 1, amountToSwap, 0)
                : cp1(pool).exchange(0, 1, amountToSwap, 0);
        }
        advanceNBlocks(1);

        // Perform 1 wash trade over 2 blocks
        amountToSwap = priceRouter.getValue(USDC, 1e6, address(coins[1]) == ETH ? WETH : coins[1]);
        uint256 coins0Received;
        _deal(address(coins[1]), address(this), amountToSwap);
        if (address(coins[1]) == ETH) {
            coins0Received = indexIsUint256OrInt128
                ? cp0Eth(pool).exchange{ value: amountToSwap }(1, 0, amountToSwap, 0)
                : cp1Eth(pool).exchange{ value: amountToSwap }(1, 0, amountToSwap, 0);
        } else {
            coins[1].safeApprove(pool, amountToSwap);
            coins0Received = indexIsUint256OrInt128
                ? cp0(pool).exchange(1, 0, amountToSwap, 0)
                : cp1(pool).exchange(1, 0, amountToSwap, 0);
        }
        advanceNBlocks(1);

        _deal(address(coins[0]), address(this), coins0Received);
        if (address(coins[0]) == ETH) {
            indexIsUint256OrInt128
                ? cp0Eth(pool).exchange{ value: coins0Received }(0, 1, coins0Received, 0)
                : cp1Eth(pool).exchange{ value: coins0Received }(0, 1, coins0Received, 0);
        } else {
            coins[0].safeApprove(pool, coins0Received);
            indexIsUint256OrInt128
                ? cp0(pool).exchange(0, 1, coins0Received, 0)
                : cp1(pool).exchange(0, 1, coins0Received, 0);
        }
        advanceNBlocks(1);

        // Return price back to normal.
        _deal(address(coins[1]), address(this), largeSwapOut);
        if (address(coins[1]) == ETH) {
            indexIsUint256OrInt128
                ? cp0Eth(pool).exchange{ value: largeSwapOut }(1, 0, largeSwapOut, 0)
                : cp1Eth(pool).exchange{ value: largeSwapOut }(1, 0, largeSwapOut, 0);
        } else {
            coins[1].safeApprove(pool, largeSwapOut);
            indexIsUint256OrInt128
                ? cp0(pool).exchange(1, 0, largeSwapOut, 0)
                : cp1(pool).exchange(1, 0, largeSwapOut, 0);
        }
        advanceNBlocks(1);
    }

    function advanceNBlocks(uint256 blocksToAdvance) internal {
        vm.roll(block.number + blocksToAdvance);
        skip(12 * blocksToAdvance);
    }

    function _getLpPriceUsingRemoveLiquidity(CurvePool pool, ERC20 lpToken) internal returns (uint256 lpPriceUsd) {
        // Use snapshot to reset state once done
        uint256 snapshot = vm.snapshot();

        deal(address(lpToken), address(this), 1e18);
        ERC20[] memory coins = new ERC20[](2);
        coins[0] = pool.coins(0) == curve2PoolExtension.CURVE_ETH() ? WETH : ERC20(pool.coins(0));
        coins[1] = pool.coins(1) == curve2PoolExtension.CURVE_ETH() ? WETH : ERC20(pool.coins(1));
        uint256[] memory deltaBalances = new uint256[](2);
        deltaBalances[0] = coins[0].balanceOf(address(this));
        deltaBalances[1] = coins[1].balanceOf(address(this));

        // This function will get a pools LP price by removing liquidity
        pool.remove_liquidity(1e18, [uint256(0), 0]);

        deltaBalances[0] = coins[0].balanceOf(address(this)) - deltaBalances[0];
        deltaBalances[1] = coins[1].balanceOf(address(this)) - deltaBalances[1];

        // Convert received assets into USDC.
        lpPriceUsd = priceRouter.getValues(coins, deltaBalances, USDC);
        // Convert USDC into USD.
        lpPriceUsd = lpPriceUsd.mulDivDown(priceRouter.getPriceInUSD(USDC), 1e6);

        vm.revertTo(snapshot);
    }

    receive() external payable {
        deal(address(WETH), address(this), WETH.balanceOf(address(this)) + msg.value);
    }

    function _deal(address token, address to, uint256 amount) internal {
        if (token == ETH) deal(to, amount);
        else if (token == address(STETH)) _takeSteth(amount, to);
        else if (token == address(OETH)) _takeOeth(amount, to);
        else deal(token, to, amount);
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

    function _add2PoolAssetToPriceRouter(
        address pool,
        address token,
        ERC20 underlyingOrConstituent0,
        ERC20 underlyingOrConstituent1,
        bool divideRate0,
        bool divideRate1,
        uint32 lowerBound,
        uint32 upperBound
    ) internal {
        Curve2PoolExtension.ExtensionStorage memory stor;
        stor.pool = pool;
        try CurvePool(pool).lp_price() {
            stor.isCorrelated = false;
        } catch {
            stor.isCorrelated = true;
        }
        stor.underlyingOrConstituent0 = address(underlyingOrConstituent0);
        stor.underlyingOrConstituent1 = address(underlyingOrConstituent1);
        stor.divideRate0 = divideRate0;
        stor.divideRate1 = divideRate1;
        PriceRouter.AssetSettings memory settings;
        settings.derivative = EXTENSION_DERIVATIVE;
        settings.source = address(curve2PoolExtension);
        stor.lowerBound = lowerBound;
        stor.upperBound = upperBound;

        priceRouter.addAsset(
            ERC20(token),
            settings,
            abi.encode(stor),
            _getLpPriceUsingRemoveLiquidity(CurvePool(pool), ERC20(token))
        );
    }
}

interface cp0 {
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external returns (uint256);
}

interface cp1 {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
}

interface cp0Eth {
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
}

interface cp1Eth {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
}
