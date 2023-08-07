// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { SinglePositionUniswapV3Adaptor } from "src/modules/adaptors/Uniswap/SinglePositionUniswapV3Adaptor.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswapV3P/libraries/LiquidityAmounts.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import "@uniswapV3C/libraries/FixedPoint128.sol";
import "@uniswapV3C/libraries/FullMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SinglePositionUniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/SinglePositionUniswapV3PositionTracker.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

// Will test the swapping and cellar position management using adaptors
contract SinglePositionUniswapV3AdaptorTest is MainnetStarterTest, AdaptorHelperFunctions, ERC721Holder {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    Cellar private cellar;

    IUniswapV3Factory internal factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    SinglePositionUniswapV3Adaptor private uniswapV3Adaptor;
    SinglePositionUniswapV3PositionTracker private tracker;

    MockDataFeed private mockUsdcUsd;
    MockDataFeed private mockDaiUsd;
    MockDataFeed private mockWethUsd;

    IUniswapV3Router public uniswapV3Router = IUniswapV3Router(uniV3Router);

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private daiPosition = 3;
    uint32 private usdcDaiPosition = 4;
    uint32 private usdcWethPosition = 5;

    uint256 public initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockUsdcUsd = new MockDataFeed(USDC_USD_FEED);
        mockDaiUsd = new MockDataFeed(DAI_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);

        tracker = new SinglePositionUniswapV3PositionTracker(positionManager);
        uniswapV3Adaptor = new SinglePositionUniswapV3Adaptor(address(positionManager), address(tracker));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(address(mockWethUsd)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWethUsd));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(mockUsdcUsd)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUsdcUsd));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(mockDaiUsd)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockDaiUsd));
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(uniswapV3Adaptor));

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(usdcDaiPosition, address(uniswapV3Adaptor), abi.encode(DAI_USDC_100, 0));
        registry.trustPosition(usdcWethPosition, address(uniswapV3Adaptor), abi.encode(USDC_WETH_500, 0));

        string memory cellarName = "UniswapV3 Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);

        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        cellar.addPositionToCatalogue(daiPosition);
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(usdcDaiPosition);
        cellar.addPositionToCatalogue(usdcWethPosition);

        cellar.addPosition(1, daiPosition, abi.encode(0), false);
        cellar.addPosition(1, wethPosition, abi.encode(0), false);
        cellar.addPosition(1, usdcDaiPosition, abi.encode(true), false);
        cellar.addPosition(1, usdcWethPosition, abi.encode(true), false);

        cellar.addAdaptorToCatalogue(address(uniswapV3Adaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        cellar.setRebalanceDeviation(0.003e18);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    // ========================================== POSITION MANAGEMENT TEST ==========================================
    function testOpenUSDC_DAIPosition() external {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate swap by dealing Cellar equal parts of USDC and DAI.
        uint256 usdcAmount = assets / 2;
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
        deal(address(USDC), address(cellar), usdcAmount + initialAssets);
        deal(address(DAI), address(cellar), daiAmount);

        // Use `callOnAdaptor` to enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 0, type(uint256).max, type(uint256).max, 10);
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        uint256 position = tracker.getTokenAtIndex(address(cellar), DAI_USDC_100, 0);

        assertEq(
            position,
            positionManager.tokenOfOwnerByIndex(address(cellar), 0),
            "Tracker should be tracking cellars first Uni NFT."
        );

        // Have user withdraw from UniV3 position.
        uint256 redeemAmount = cellar.maxRedeem(address(this));
        cellar.redeem(redeemAmount, address(this), address(this));
        uint256 userValueOut = USDC.balanceOf(address(this)) +
            priceRouter.getValue(DAI, DAI.balanceOf(address(this)), USDC);

        assertApproxEqRel(userValueOut, assets, 0.0001e18, "User value out should equal assets in.");
    }

    // TODO tests trying each adaptor function.

    function testManipulatePoolTickUpTowardRealPrice() external {
        // User deposits into Cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        mockUsdcUsd.setMockAnswer(0.999e8);
        mockDaiUsd.setMockAnswer(1.001e8);

        // Strategist rebalances into UniV3 position.
        // Simulate swap by dealing Cellar equal parts of USDC and DAI.
        uint256 usdcAmount = assets / 2;
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
        deal(address(USDC), address(cellar), usdcAmount + initialAssets);
        deal(address(DAI), address(cellar), daiAmount);

        // Use `callOnAdaptor` to enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 0, type(uint256).max, type(uint256).max, 10);
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Attacker skews pool tick down.
        uint256 swapAmount = 10_000_000e6;
        deal(address(USDC), address(this), swapAmount);
        swapWithUniV3(USDC, DAI, 100, swapAmount);
        deal(address(USDC), address(this), 0);
        deal(address(DAI), address(this), 0);

        uint256 redeemAmount = cellar.maxRedeem(address(this));
        cellar.redeem(redeemAmount, address(this), address(this));
        uint256 userValueOut = USDC.balanceOf(address(this)) +
            priceRouter.getValue(DAI, DAI.balanceOf(address(this)), USDC);

        // assertGt(totalAssetsBeforeAttack, totalAssetsAfterAttack, "Total Assets should have gone down.");
    }

    // So my hypothesis is that the max value extractable out is based on the delta between derived tick, and the fair market uniV3 tick.
    // Like when the dervied tick is off from the actual UniV3 tick , if an attacker withdraws from the LP position they will get a larger value out than expected.
    // As the derived tick becomes more accurate, the extra value decreases to zero.

    function testDerivedTickFairMarketTickDeltaInfluenceOnPositionValue(uint256 chainlinkError) external {
        chainlinkError = bound(chainlinkError, 0.90e4, 1.1e4);
        IUniswapV3Pool pool = IUniswapV3Pool(USDC_WETH_500);
        ERC20 token0 = USDC;
        ERC20 token1 = WETH;

        // Set current chainlink answer to be extremely close to uniV3 pool tick.
        {
            uint256 currentAnswer = priceRouter.getPriceInUSD(WETH);
            mockWethUsd.setMockAnswer(int256(currentAnswer.mulDivDown(1.0002e4, 1e4)));

            // Skew chainlink dervied answer.
            currentAnswer = priceRouter.getPriceInUSD(WETH);
            mockWethUsd.setMockAnswer(int256(currentAnswer.mulDivDown(chainlinkError, 1e4)));
        }

        uint256 poolAmount0;
        uint256 poolAmount1;
        uint256 chainlinkAmount0;
        uint256 chainlinkAmount1;

        {
            // Tick to use for LP position.
            int24 lower = 201400;
            int24 upper = 201600;

            (uint160 poolSqrtPriceX96, , , , , , ) = pool.slot0();

            // Chainlink derived sqrtPriceX96.
            uint160 chainlinkSqrtPriceX96;
            {
                uint256 precisionPrice;
                uint256 baseToUSD = priceRouter.getPriceInUSD(token1);
                uint256 quoteToUSD = priceRouter.getPriceInUSD(token0);
                baseToUSD = baseToUSD * 1e18; // Multiply by 1e18 to keep some precision.
                precisionPrice = baseToUSD.mulDivDown(10 ** token0.decimals(), quoteToUSD);
                uint256 ratioX192 = ((10 ** token1.decimals()) << 192) / (precisionPrice / 1e18);
                chainlinkSqrtPriceX96 = uint160(_sqrt(ratioX192));
            }

            uint128 liquidity = 1e18;

            (poolAmount0, poolAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                poolSqrtPriceX96,
                TickMath.getSqrtRatioAtTick(lower),
                TickMath.getSqrtRatioAtTick(upper),
                liquidity
            );

            (chainlinkAmount0, chainlinkAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                chainlinkSqrtPriceX96,
                TickMath.getSqrtRatioAtTick(lower),
                TickMath.getSqrtRatioAtTick(upper),
                liquidity
            );
        }

        uint256 poolValue = poolAmount0 + priceRouter.getValue(WETH, poolAmount1, USDC);
        uint256 chainlinkValue = chainlinkAmount0 + priceRouter.getValue(WETH, chainlinkAmount1, USDC);

        chainlinkError = chainlinkError < 1e4 ? 2e4 - chainlinkError : chainlinkError;

        uint256 realError = (1e4 * poolValue) / chainlinkValue;

        if (chainlinkError != realError)
            assertGt(chainlinkError, realError, "Chainlink price error should always be greater than real error.");

        assertApproxEqRel(
            (realError ** 2) / 1e4,
            chainlinkError,
            0.01e18,
            "Real error squared should approximately equal chainlink error."
        );
    }

    function testAttackerFillsRangeOrder() external {
        // User deposits into Cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Stategist places range order.
        int24 lower = 203000;
        int24 upper = 203010;

        // Use `callOnAdaptor` to enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                SinglePositionUniswapV3Adaptor.openPosition.selector,
                USDC_WETH_500,
                0,
                assets,
                0,
                0,
                0,
                lower,
                upper
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 attackerValueIn = assets;
        uint256 attackerValueOut;

        // Attacker skews pool tick up.
        uint256 ethSwapAmount = 35_000e18;
        deal(address(WETH), address(this), ethSwapAmount);
        swapWithUniV3(WETH, USDC, 500, ethSwapAmount);

        attackerValueIn += priceRouter.getValue(WETH, ethSwapAmount, USDC);
        attackerValueOut = USDC.balanceOf(address(this));

        deal(address(USDC), address(this), 0);
        deal(address(WETH), address(this), 0);

        // Now that range order is filled have the attacker withdraw.
        uint256 maxRedeem = cellar.maxRedeem(address(this));
        cellar.redeem(maxRedeem, address(this), address(this));

        uint256 redeemValue = USDC.balanceOf(address(this)) +
            priceRouter.getValue(WETH, WETH.balanceOf(address(this)), USDC);

        assertGt(redeemValue, assets, "Attacker should get more assets out than they put in.");

        attackerValueOut += redeemValue;

        deal(address(USDC), address(this), 0);
        deal(address(WETH), address(this), 0);

        uint256 price = derivePriceAtTick(USDC_WETH_500);
        console.log("price", price);

        // Attacker moves pool tick back to where it was.
        uint256 usdcSwapAmount = 58_200_000e6;
        deal(address(USDC), address(this), usdcSwapAmount);
        swapWithUniV3(USDC, WETH, 500, usdcSwapAmount);

        attackerValueIn += usdcSwapAmount;
        attackerValueOut += priceRouter.getValue(WETH, WETH.balanceOf(address(this)), USDC);

        assertGt(attackerValueIn, attackerValueOut, "Attacker should have lost money.");
    }

    // function testManipulatePoolTickUpAwayFromRealPrice() external {
    //     // User deposits into Cellar.
    //     uint256 assets = 100_000e6;
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // mockUsdcUsd.setMockAnswer(0.999e8);
    //     // mockDaiUsd.setMockAnswer(1.001e8);

    //     // Strategist rebalances into UniV3 position.
    //     // Simulate swap by dealing Cellar equal parts of USDC and DAI.
    //     uint256 usdcAmount = assets / 2;
    //     uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
    //     deal(address(USDC), address(cellar), usdcAmount + initialAssets);
    //     deal(address(DAI), address(cellar), daiAmount);

    //     // Use `callOnAdaptor` to enter UniV3 position.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 0, type(uint256).max, type(uint256).max, 10);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
    //     }
    //     cellar.callOnAdaptor(data);

    //     // Get current stats.
    //     uint256 totalAssetsBeforeAttack = cellar.totalAssets();

    //     // Attacker skews pool tick down.
    //     uint256 swapAmount = 10_000_000e18;
    //     deal(address(USDC), address(this), swapAmount);
    //     swapWithUniV3(USDC, DAI, 100, swapAmount);

    //     uint256 totalAssetsAfterAttack = cellar.totalAssets();

    //     assertGt(totalAssetsAfterAttack, totalAssetsBeforeAttack, "Total Assets should have gone up.");
    // }

    // function testManipulatePoolTickDownTowardRealPrice() external {
    //     // User deposits into Cellar.
    //     uint256 assets = 100_000e6;
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // mockUsdcUsd.setMockAnswer(0.999e8);
    //     // mockDaiUsd.setMockAnswer(1.001e8);

    //     // Strategist rebalances into UniV3 position.
    //     // Simulate swap by dealing Cellar equal parts of USDC and DAI.
    //     uint256 usdcAmount = assets / 2;
    //     uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
    //     deal(address(USDC), address(cellar), usdcAmount + initialAssets);
    //     deal(address(DAI), address(cellar), daiAmount);

    //     // Use `callOnAdaptor` to enter UniV3 position.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 0, type(uint256).max, type(uint256).max, 10);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
    //     }
    //     cellar.callOnAdaptor(data);

    //     // Get current stats.
    //     uint256 totalAssetsBeforeAttack = cellar.totalAssets();

    //     // Attacker skews pool tick down.
    //     uint256 swapAmount = 10_000_000e18;
    //     deal(address(DAI), address(this), swapAmount);
    //     swapWithUniV3(DAI, USDC, 100, swapAmount);

    //     uint256 totalAssetsAfterAttack = cellar.totalAssets();

    //     assertGt(totalAssetsBeforeAttack, totalAssetsAfterAttack, "Total Assets should have gone down.");
    // }

    // function testManipulatePoolTickDownAwayFromRealPrice() external {
    //     // User deposits into Cellar.
    //     uint256 assets = 100_000e6;
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     mockUsdcUsd.setMockAnswer(0.999e8);
    //     mockDaiUsd.setMockAnswer(1.001e8);

    //     // Strategist rebalances into UniV3 position.
    //     // Simulate swap by dealing Cellar equal parts of USDC and DAI.
    //     uint256 usdcAmount = assets / 2;
    //     uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
    //     deal(address(USDC), address(cellar), usdcAmount + initialAssets);
    //     deal(address(DAI), address(cellar), daiAmount);

    //     // Use `callOnAdaptor` to enter UniV3 position.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 0, type(uint256).max, type(uint256).max, 10);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
    //     }
    //     cellar.callOnAdaptor(data);

    //     // Get current stats.
    //     uint256 totalAssetsBeforeAttack = cellar.totalAssets();

    //     // Attacker skews pool tick down.
    //     uint256 swapAmount = 10_000_000e18;
    //     deal(address(DAI), address(this), swapAmount);
    //     swapWithUniV3(DAI, USDC, 100, swapAmount);

    //     uint256 totalAssetsAfterAttack = cellar.totalAssets();

    //     assertGt(totalAssetsAfterAttack, totalAssetsBeforeAttack, "Total Assets should have gone up.");
    // }

    // // TODO test checking isLiquid.

    // function testAttackerFillingFarOffRangeOrder() external {
    //     // User deposits into Cellar.
    //     uint256 assets = 100_000e6;
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     int24 upper = 202810;
    //     int24 lower = 202000;

    //     // Use `callOnAdaptor` to enter UniV3 position.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = abi.encodeWithSelector(
    //             SinglePositionUniswapV3Adaptor.openPosition.selector,
    //             USDC_WETH_500,
    //             0,
    //             assets,
    //             0,
    //             0,
    //             0,
    //             lower,
    //             upper
    //         );
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
    //     }
    //     cellar.callOnAdaptor(data);

    //     uint256 totalAssetsBeforeAttack = cellar.totalAssets();

    //     // Attacker skews pool tick down.
    //     uint256 swapAmount = 30_000e18;
    //     deal(address(WETH), address(this), swapAmount);
    //     swapWithUniV3(WETH, USDC, 500, swapAmount);

    //     uint256 totalAssetsAfterAttack = cellar.totalAssets();

    //     assertGt(totalAssetsAfterAttack, totalAssetsBeforeAttack, "Total Assets should have gone up.");

    //     uint256 attackerValuePaid = priceRouter.getValue(WETH, swapAmount, USDC) - USDC.balanceOf(address(this));
    //     uint256 totalAssetsDelta = totalAssetsAfterAttack - totalAssetsBeforeAttack;

    //     assertLt(
    //         totalAssetsDelta * 100,
    //         attackerValuePaid,
    //         "Attacker value paid should be much greater than total assets increase."
    //     );
    // }

    // ========================================= GRAVITY FUNCTIONS =========================================

    // Since this contract is set as the Gravity Bridge, this will be called by
    // the Cellar's `sendFees` function to send funds Cosmos.
    function sendToCosmos(address asset, bytes32, uint256 assets) external {
        ERC20(asset).transferFrom(msg.sender, cosmos, assets);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function derivePriceAtTick(address pool) internal view returns (uint256 priceToken1OverToken0) {
        IUniswapV3Pool _pool = IUniswapV3Pool(pool);
        ERC20 token0 = ERC20(_pool.token0());
        ERC20 token1 = ERC20(_pool.token1());

        (uint256 sqrtPriceX96, , , , , , ) = _pool.slot0();
        // Scale answer to preserve precision.
        sqrtPriceX96 *= 1e18;
        sqrtPriceX96 = sqrtPriceX96 >> 96;
        sqrtPriceX96 = sqrtPriceX96 ** 2;
        priceToken1OverToken0 = sqrtPriceX96.mulDivDown(10 ** token0.decimals(), 10 ** (token1.decimals() + 18));
    }

    function _printTick(address pool) internal view {
        IUniswapV3Pool _pool = IUniswapV3Pool(pool);
        (, int24 tick, , , , , ) = _pool.slot0();

        if (tick < 0) console.log("Tick (-):", uint24(tick * -1));
        else console.log("Tick (+):", uint24(tick));
    }

    function swapWithUniV3(
        ERC20 assetIn,
        ERC20 assetOut,
        uint24 poolFee,
        uint256 amount
    ) public returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = address(assetIn);
        path[1] = address(assetOut);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = poolFee;
        uint256 amountOutMin = 0;

        // Approve assets to be swapped through the router.
        assetIn.safeApprove(address(uniswapV3Router), amount);

        // Encode swap parameters.
        bytes memory encodePackedPath = abi.encodePacked(address(assetIn));
        for (uint256 i = 1; i < path.length; i++)
            encodePackedPath = abi.encodePacked(encodePackedPath, poolFees[i - 1], path[i]);

        // Execute the swap.
        amountOut = uniswapV3Router.exactInput(
            IUniswapV3Router.ExactInputParams({
                path: encodePackedPath,
                recipient: address(this),
                deadline: block.timestamp + 60,
                amountIn: amount,
                amountOutMinimum: amountOutMin
            })
        );
    }

    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }

    /**
     * @notice Get the upper and lower tick around token0, token1.
     * @param token0 The 0th Token in the UniV3 Pair
     * @param token1 The 1st Token in the UniV3 Pair
     * @param fee The desired fee pool
     * @param size Dictates the amount of ticks liquidity will cover
     *             @dev Must be an even number
     * @param shift Allows the upper and lower tick to be moved up or down relative
     *              to current price. Useful for range orders.
     */
    function _getUpperAndLowerTick(
        address token0,
        address token1,
        uint24 fee,
        int24 size,
        int24 shift
    ) internal view returns (int24 lower, int24 upper) {
        // uint256 price = priceRouter.getExchangeRate(ERC20(token1), ERC20(token0));
        // uint256 ratioX192 = ((10 ** ERC20(token1).decimals()) << 192) / (price);
        // uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(ratioX192));
        // int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));
        (, int24 tick, , , , , ) = pool.slot0();
        tick = tick + shift;
        int24 spacing = pool.tickSpacing();
        lower = tick - (tick % spacing);
        lower = lower - ((spacing * size) / 2);
        upper = lower + spacing * size;
    }

    function _createBytesDataToOpenLP(
        address pool,
        uint256 index,
        uint256 amount0,
        uint256 amount1,
        int24 size
    ) internal view returns (bytes memory) {
        IUniswapV3Pool _pool = IUniswapV3Pool(pool);
        (int24 lower, int24 upper) = _getUpperAndLowerTick(_pool.token0(), _pool.token1(), _pool.fee(), size, 0);
        return
            abi.encodeWithSelector(
                SinglePositionUniswapV3Adaptor.openPosition.selector,
                pool,
                index,
                amount0,
                amount1,
                0,
                0,
                lower,
                upper
            );
    }

    function _createBytesDataToCloseLP(address pool, uint256 index) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SinglePositionUniswapV3Adaptor.closePosition.selector, pool, index, 0, 0);
    }

    function _createBytesDataToAddLP(
        address pool,
        uint256 index,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                SinglePositionUniswapV3Adaptor.addToPosition.selector,
                pool,
                index,
                amount0,
                amount1,
                0,
                0
            );
    }

    function _createBytesDataToTakeLP(
        address owner,
        uint256 index,
        uint256 liquidityPer,
        bool takeFees
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        uint128 liquidity;
        if (liquidityPer >= 1e18) liquidity = type(uint128).max;
        else {
            (, , , , , , , uint128 positionLiquidity, , , , ) = positionManager.positions(tokenId);
            liquidity = uint128((positionLiquidity * liquidityPer) / 1e18);
        }
        return
            abi.encodeWithSelector(
                SinglePositionUniswapV3Adaptor.takeFromPosition.selector,
                tokenId,
                liquidity,
                0,
                0,
                takeFees
            );
    }

    function _createBytesDataToCollectFees(
        address owner,
        uint256 index,
        uint128 amount0,
        uint128 amount1
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(SinglePositionUniswapV3Adaptor.collectFees.selector, tokenId, amount0, amount1);
    }

    function _createBytesDataToPurgePosition(address pool, uint256 index) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SinglePositionUniswapV3Adaptor.purgeSinglePosition.selector, pool, index);
    }

    function _createBytesDataToRemoveTrackedPositionNotOwned(
        address pool,
        uint256 index
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                SinglePositionUniswapV3Adaptor.removeUnOwnedPositionFromTracker.selector,
                pool,
                index
            );
    }

    // function _createBytesDataToOpenRangeOrder(
    //     ERC20 token0,
    //     ERC20 token1,
    //     uint24 poolFee,
    //     uint256 amount0,
    //     uint256 amount1
    // ) internal view returns (bytes memory) {
    //     int24 lower;
    //     int24 upper;
    //     if (amount0 > 0) {
    //         (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, 100);
    //     } else {
    //         (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, -100);
    //     }

    //     return
    //         abi.encodeWithSelector(
    //             SinglePositionUniswapV3Adaptor.openPosition.selector,
    //             token0,
    //             token1,
    //             poolFee,
    //             amount0,
    //             amount1,
    //             0,
    //             0,
    //             lower,
    //             upper
    //         );
    // }

    // Used to spoof adaptor into thinkig this is a cellar contract.
    function isPositionUsed(uint256) public pure returns (bool) {
        return true;
    }
}
