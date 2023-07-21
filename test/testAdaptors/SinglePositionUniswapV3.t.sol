// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { SinglePositionUniswapV3Adaptor } from "src/modules/adaptors/Uniswap/SinglePositionUniswapV3Adaptor.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
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
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";

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
    SwapRouter private swapRouter;

    IUniswapV3Factory internal factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    SinglePositionUniswapV3Adaptor private singlePositionUniswapV3Adaptor;
    SinglePositionUniswapV3PositionTracker private tracker;

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private daiPosition = 3;
    uint32 private usdcDaiPosition100_0 = 4;
    uint32 private usdcDaiPosition100_1 = 5;
    uint32 private usdcDaiPosition500_0 = 6;
    uint32 private usdcDaiPosition500_1 = 7;
    uint32 private usdcUsdtPosition100_0 = 8;

    uint32 private usdcWethPosition500_0 = 9;

    uint256 public initialAssets;
    // Stable Pairs
    address public DAI_USDC_100 = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    address public DAI_USDC_500 = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;
    address public USDC_USDT_100 = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;
    address public USDC_USDT_500 = 0x7858E59e0C01EA06Df3aF3D20aC7B0003275D4Bf;

    // Volatile Pairs
    address public USDC_WETH_500 = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        tracker = new SinglePositionUniswapV3PositionTracker(positionManager);
        singlePositionUniswapV3Adaptor = new SinglePositionUniswapV3Adaptor(address(positionManager), address(tracker));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(singlePositionUniswapV3Adaptor));

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));

        // Create UniV3 Positions.
        registry.trustPosition(
            usdcDaiPosition100_0,
            address(singlePositionUniswapV3Adaptor),
            abi.encode(DAI_USDC_100, 0)
        );
        registry.trustPosition(
            usdcDaiPosition100_1,
            address(singlePositionUniswapV3Adaptor),
            abi.encode(DAI_USDC_100, 1)
        );
        registry.trustPosition(
            usdcDaiPosition500_0,
            address(singlePositionUniswapV3Adaptor),
            abi.encode(DAI_USDC_500, 0)
        );
        registry.trustPosition(
            usdcDaiPosition500_1,
            address(singlePositionUniswapV3Adaptor),
            abi.encode(DAI_USDC_500, 1)
        );
        // registry.trustPosition(
        //     usdcUsdtPosition100_0,
        //     address(singlePositionUniswapV3Adaptor),
        //     abi.encode(USDC_USDT_100, 0)
        // );

        registry.trustPosition(
            usdcWethPosition500_0,
            address(singlePositionUniswapV3Adaptor),
            abi.encode(USDC_WETH_500, 0)
        );

        string memory cellarName = "UniswapV3 Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);

        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        cellar.addPositionToCatalogue(daiPosition);
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(usdcDaiPosition100_0);
        cellar.addPositionToCatalogue(usdcDaiPosition100_1);
        cellar.addPositionToCatalogue(usdcDaiPosition500_0);
        cellar.addPositionToCatalogue(usdcDaiPosition500_1);
        // cellar.addPositionToCatalogue(usdcUsdtPosition100_0);
        cellar.addPositionToCatalogue(usdcWethPosition500_0);

        cellar.addPosition(1, daiPosition, abi.encode(0), false);
        cellar.addPosition(2, usdcDaiPosition100_0, abi.encode(true), false);
        cellar.addPosition(3, usdcDaiPosition100_1, abi.encode(true), false);
        cellar.addPosition(4, usdcDaiPosition500_0, abi.encode(true), false);
        cellar.addPosition(5, usdcDaiPosition500_1, abi.encode(true), false);

        cellar.addAdaptorToCatalogue(address(singlePositionUniswapV3Adaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        cellar.setRebalanceDeviation(0.003e18);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    // ========================================== POSITION MANAGEMENT TEST ==========================================
    function testUserWithdrawFromLP(uint256 assets) external {
        cellar.swapPositions(5, 0, false);

        assets = bound(assets, 1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 usdcAmount = assets / 2;
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
        deal(address(USDC), address(cellar), usdcAmount + initialAssets);
        deal(address(DAI), address(cellar), daiAmount);

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 0, type(uint256).max, type(uint256).max, 10);
            data[0] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
        uint256 position = tracker.getTokenAtIndex(address(cellar), DAI_USDC_100, 0);
        assertGt(position, 0, "Tracker should have a nonzero position at index 0.");
        assertEq(
            position,
            positionManager.tokenOfOwnerByIndex(address(cellar), 0),
            "Tracker should be tracking cellars first Uni NFT."
        );

        // Save share price.
        uint256 sharePrice = cellar.previewRedeem(10 ** cellar.decimals());
        // Try to withdraw half of the deposit.
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this)) / 2;
        assertApproxEqRel(assets / 2, amountToWithdraw, 0.001e18, "Max Withdraw should equal assets in.");
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        uint256 valueOut = priceRouter.getValue(DAI, DAI.balanceOf(address(this)), USDC) +
            USDC.balanceOf(address(this));
        assertApproxEqAbs(valueOut, amountToWithdraw, 1, "Value out should equal amountToWithdraw");

        assertApproxEqAbs(
            cellar.previewRedeem(10 ** cellar.decimals()),
            sharePrice,
            1,
            "Share price should not have changed from withdraw."
        );
    }

    function testMultiplePositionsInTheSamePool(uint256 assets) external {
        assets = bound(assets, 1e6, 10_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a swap by altering Cellars stablecoin balances.
        uint256 usdcAmount = assets / 2;
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
        deal(address(USDC), address(cellar), usdcAmount + initialAssets);
        deal(address(DAI), address(cellar), daiAmount);

        // Strategist enters 2 UniV3 Positions in the same pool.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 0, daiAmount / 2, usdcAmount / 2, 10);
            data[0] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 1, type(uint256).max, assets / 4, 10);
            data[1] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 position0 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_100, 0);
        assertEq(
            position0,
            positionManager.tokenOfOwnerByIndex(address(cellar), 0),
            "Tracker should be tracking cellars first Uni NFT."
        );
        uint256 position1 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_100, 1);
        assertEq(
            position1,
            positionManager.tokenOfOwnerByIndex(address(cellar), 1),
            "Tracker should be tracking cellars second Uni NFT."
        );

        uint256 maxWithdraw = cellar.maxWithdraw(address(this));
        assertApproxEqRel(assets, maxWithdraw, 0.0001e18, "User max withdraw should equal assets in.");

        cellar.withdraw(maxWithdraw, address(this), address(this));
        uint256 valueOut = priceRouter.getValue(DAI, DAI.balanceOf(address(this)), USDC) +
            USDC.balanceOf(address(this));
        assertApproxEqAbs(valueOut, maxWithdraw, 2, "Value out should equal maxWithdraw");
    }

    function testMultiplePositionsInTheSameAndDifferentPools(uint256 assets) external {
        // Move USDC position to end of withdraw queue so we pull liquidity from all UniV3 positions with user withdraw.
        cellar.swapPositions(5, 0, false);
        assets = bound(assets, 1e6, 10_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a swap by altering Cellars stablecoin balances.
        uint256 usdcAmount = assets / 2;
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
        deal(address(USDC), address(cellar), usdcAmount + initialAssets);
        deal(address(DAI), address(cellar), daiAmount);

        // Strategist enters 4 UniV3 Positions 2 in each pool.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](4);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 0, daiAmount / 4, usdcAmount / 4, 10);
            data[0] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_100, 1, daiAmount / 4, usdcAmount / 4, 10);
            data[1] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_500, 0, daiAmount / 4, usdcAmount / 4, 10);
            data[2] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(DAI_USDC_500, 1, type(uint256).max, type(uint256).max, 10);
            data[3] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 position0 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_100, 0);
        assertEq(
            position0,
            positionManager.tokenOfOwnerByIndex(address(cellar), 0),
            "Tracker should be tracking cellars first Uni NFT."
        );
        uint256 position1 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_100, 1);
        assertEq(
            position1,
            positionManager.tokenOfOwnerByIndex(address(cellar), 1),
            "Tracker should be tracking cellars second Uni NFT."
        );

        uint256 position2 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_500, 0);
        assertEq(
            position2,
            positionManager.tokenOfOwnerByIndex(address(cellar), 2),
            "Tracker should be tracking cellars third Uni NFT."
        );
        uint256 position3 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_500, 1);
        assertEq(
            position3,
            positionManager.tokenOfOwnerByIndex(address(cellar), 3),
            "Tracker should be tracking cellars fourth Uni NFT."
        );

        // Strategist now closes the 0 index positions.
        data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToCloseLP(DAI_USDC_100, 0);
            data[0] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToCloseLP(DAI_USDC_500, 0);
            data[1] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Make sure correct indexes were updated in tracker.
        position0 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_100, 0);
        assertEq(position0, 0, "Tracker should be 0.");
        uint256 newPosition1 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_100, 1);
        assertEq(newPosition1, position1, "Tracker should be still be tracking this position.");

        position2 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_500, 0);
        assertEq(position2, 0, "Tracker should be 0.");
        uint256 newPosition3 = tracker.getTokenAtIndex(address(cellar), DAI_USDC_500, 1);
        assertEq(newPosition3, position3, "Tracker should be still be tracking this position.");

        // User withdraws when 2 LP positions have zero assets.
        uint256 maxWithdraw = cellar.maxWithdraw(address(this));
        assertApproxEqRel(assets, maxWithdraw, 0.0001e18, "User max withdraw should equal assets in.");

        cellar.withdraw(maxWithdraw, address(this), address(this));
        uint256 valueOut = priceRouter.getValue(DAI, DAI.balanceOf(address(this)), USDC) +
            USDC.balanceOf(address(this));
        assertApproxEqAbs(valueOut, maxWithdraw, 2, "Value out should equal maxWithdraw");

        // Strategist now closes the 1 index positions.
        data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToPurgePosition(DAI_USDC_100, 1);
            data[0] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToPurgePosition(DAI_USDC_500, 1);
            data[1] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
    }

    function testAttackerSkewingStablePoolTickUp() external {
        address attacker = vm.addr(34);
        uint256 assets = 1_000_000e6;
        deal(address(USDC), attacker, assets);
        vm.startPrank(attacker);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, attacker);
        vm.stopPrank();

        uint256 usdcAmount = assets / 2;
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
        deal(address(USDC), address(cellar), usdcAmount + initialAssets);
        deal(address(DAI), address(cellar), daiAmount);

        // Strategsit LPs.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        int24 lower = -276325;
        int24 upper = -276323;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLPWithTicks(
                DAI_USDC_100,
                0,
                type(uint256).max,
                type(uint256).max,
                lower,
                upper
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 totalAssetsBeforeAttack = cellar.totalAssets();

        // Attacker skews pool tick.
        IUniswapV3Pool pool = IUniswapV3Pool(DAI_USDC_100);
        uint256 swapAmount = 47_675_000e6;
        deal(address(USDC), address(this), swapAmount);
        bytes memory swapData = _createBytesDataForSwapWithUniv3(USDC, DAI, 100, swapAmount);
        address(swapWithUniswapAdaptor).functionDelegateCall(swapData);

        uint256 totalAssetsAfterAttack = cellar.totalAssets();
        // Since USDC is worth more than DAI according to Chainlink TotalAssets increases.
        assertGt(totalAssetsAfterAttack, totalAssetsBeforeAttack, "Attack should have increased total assets.");
        uint256 totalAssetsDelta = totalAssetsAfterAttack - totalAssetsBeforeAttack;
        uint256 feeAttackerPaidToManipulateTick = swapAmount / 10_000; // Fee is 0.01%;

        assertGt(
            feeAttackerPaidToManipulateTick,
            totalAssetsDelta,
            "Fee paid should be larger than total assets increase."
        );
    }

    function testAttackerSkewingStablePoolTickDown() external {
        address attacker = vm.addr(34);
        uint256 assets = 1_000_000e6;
        deal(address(USDC), attacker, assets);
        vm.startPrank(attacker);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, attacker);
        vm.stopPrank();

        uint256 usdcAmount = assets / 2;
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 2, DAI);
        deal(address(USDC), address(cellar), usdcAmount + initialAssets);
        deal(address(DAI), address(cellar), daiAmount);

        // Strategsit LPs.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        int24 lower = -276325;
        int24 upper = -276323;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLPWithTicks(
                DAI_USDC_100,
                0,
                type(uint256).max,
                type(uint256).max,
                lower,
                upper
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 totalAssetsBeforeAttack = cellar.totalAssets();

        // Attacker skews pool tick.
        IUniswapV3Pool pool = IUniswapV3Pool(DAI_USDC_100);
        uint256 swapAmount = 10_000_000e18;
        deal(address(DAI), address(this), swapAmount);
        bytes memory swapData = _createBytesDataForSwapWithUniv3(DAI, USDC, 100, swapAmount);
        address(swapWithUniswapAdaptor).functionDelegateCall(swapData);

        uint256 totalAssetsAfterAttack = cellar.totalAssets();
        // Since USDC is worth more than DAI according to Chainlink TotalAssets decreases.
        assertLt(totalAssetsAfterAttack, totalAssetsBeforeAttack, "Attack should have decreases total assets.");
        uint256 totalAssetsDelta = totalAssetsBeforeAttack - totalAssetsAfterAttack;
        uint256 feeAttackerPaidToManipulateTick = swapAmount / 10_000; // Fee is 0.01%;

        assertGt(
            feeAttackerPaidToManipulateTick,
            totalAssetsDelta,
            "Fee paid should be larger than total assets increase."
        );
    }

    function testAttackerSkewingVolatilePoolTickUp() external {
        // Change Cellars positions.
        cellar.addPosition(1, wethPosition, abi.encode(0), false);
        cellar.addPosition(2, usdcWethPosition500_0, abi.encode(true), false);
        cellar.removePosition(3, false);
        cellar.removePosition(3, false);
        cellar.removePosition(3, false);
        cellar.removePosition(3, false);
        cellar.removePosition(3, false);

        address attacker = vm.addr(34);
        uint256 assets = 1_000_000e6;
        deal(address(USDC), attacker, assets);
        vm.startPrank(attacker);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, attacker);
        vm.stopPrank();

        uint256 usdcAmount = assets / 2;
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH);
        deal(address(USDC), address(cellar), usdcAmount + initialAssets);
        deal(address(WETH), address(cellar), wethAmount);

        // Strategsit LPs.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        int24 lower = 201490;
        int24 upper = 201510;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLPWithTicks(
                USDC_WETH_500,
                0,
                type(uint256).max,
                type(uint256).max,
                lower,
                upper
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 totalAssetsBeforeAttack = cellar.totalAssets();

        // Attacker skews pool tick.
        IUniswapV3Pool pool = IUniswapV3Pool(USDC_WETH_500);
        uint256 swapAmount = 1_100e18;
        deal(address(WETH), address(this), swapAmount);
        bytes memory swapData = _createBytesDataForSwapWithUniv3(WETH, USDC, 500, swapAmount);
        address(swapWithUniswapAdaptor).functionDelegateCall(swapData);

        uint256 totalAssetsAfterAttack = cellar.totalAssets();

        assertGt(totalAssetsAfterAttack, totalAssetsBeforeAttack, "Attack should have increased total assets.");
        uint256 totalAssetsDelta = totalAssetsAfterAttack - totalAssetsBeforeAttack;
        uint256 feeAttackerPaidToManipulateTick = swapAmount.mulDivDown(5, 10_000); // Fee is 0.05%;
        feeAttackerPaidToManipulateTick - priceRouter.getValue(WETH, feeAttackerPaidToManipulateTick, USDC);

        assertGt(
            feeAttackerPaidToManipulateTick,
            totalAssetsDelta,
            "Fee paid should be larger than total assets increase."
        );
    }

    function testAttackerSkewingVolatilePoolTickDown() external {
        // Change Cellars positions.
        cellar.addPosition(1, wethPosition, abi.encode(0), false);
        cellar.addPosition(2, usdcWethPosition500_0, abi.encode(true), false);
        cellar.removePosition(3, false);
        cellar.removePosition(3, false);
        cellar.removePosition(3, false);
        cellar.removePosition(3, false);
        cellar.removePosition(3, false);

        address attacker = vm.addr(34);
        uint256 assets = 1_000_000e6;
        deal(address(USDC), attacker, assets);
        vm.startPrank(attacker);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, attacker);
        vm.stopPrank();

        uint256 usdcAmount = assets / 2;
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH);
        deal(address(USDC), address(cellar), usdcAmount + initialAssets);
        deal(address(WETH), address(cellar), wethAmount);

        // Strategsit LPs.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        int24 lower = 201490;
        int24 upper = 201510;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLPWithTicks(
                USDC_WETH_500,
                0,
                type(uint256).max,
                type(uint256).max,
                lower,
                upper
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(singlePositionUniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 totalAssetsBeforeAttack = cellar.totalAssets();

        // Attacker skews pool tick.
        IUniswapV3Pool pool = IUniswapV3Pool(USDC_WETH_500);
        _printTick(pool);
        uint256 swapAmount = 1_300_000e6;
        deal(address(USDC), address(this), swapAmount);
        bytes memory swapData = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, swapAmount);
        address(swapWithUniswapAdaptor).functionDelegateCall(swapData);
        _printTick(pool);

        uint256 totalAssetsAfterAttack = cellar.totalAssets();

        assertGt(totalAssetsAfterAttack, totalAssetsBeforeAttack, "Attack should have increased total assets.");
        uint256 totalAssetsDelta = totalAssetsAfterAttack - totalAssetsBeforeAttack;
        uint256 feeAttackerPaidToManipulateTick = swapAmount.mulDivDown(5, 10_000); // Fee is 0.05%;

        console.log("totalAssetsDelta", totalAssetsDelta);
        console.log("feeAttackerPaidToManipulateTick", feeAttackerPaidToManipulateTick);

        assertGt(
            feeAttackerPaidToManipulateTick,
            totalAssetsDelta,
            "Fee paid should be larger than total assets increase."
        );
    }

    // TLDR attackers can manipulate the total assets of a cellar by manipulating a pool tick the Cellar is LPing...
    // The attack scope seems to be that whatever money is in UniV3 can be converted into either token0, token1, or a mixture of the two.
    // This can be used to raise or lower the Cellars totalAssets by taking advantage of the fact that the exchange rate on UniV3 is different from chainlink datafeeds.

    function _printTick(IUniswapV3Pool pool) internal view {
        (, int24 tick, , , , , ) = pool.slot0();
        if (tick < 0) console.log("Tick (-)", uint24(-1 * tick));
        else console.log("Tick (+)", uint24(tick));
    }

    // TODO attack tests where user skews pool tick before exitting, make sure cellar total assets only increases.
    // this also checks pulling assets from mixed orders, or single token withdraws
    // TODO test to make sure isLiquid works.
    // TODO revert tests where we try to overwrite positions, or add to positions that aren't setup.
    // TODO test where cellar has traditional Uniswap V3 illiquid positions, and new single position in the same pool

    // ========================================= GRAVITY FUNCTIONS =========================================

    // Since this contract is set as the Gravity Bridge, this will be called by
    // the Cellar's `sendFees` function to send funds Cosmos.
    function sendToCosmos(address asset, bytes32, uint256 assets) external {
        ERC20(asset).transferFrom(msg.sender, cosmos, assets);
    }

    // ========================================= HELPER FUNCTIONS =========================================
    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }

    function _getUpperAndLowerTick(
        IUniswapV3Pool pool,
        int24 size,
        int24 shift
    ) internal view returns (int24 lower, int24 upper) {
        ERC20 token1 = ERC20(pool.token1());
        ERC20 token0 = ERC20(pool.token0());
        uint256 price = priceRouter.getExchangeRate(token1, token0);
        uint256 ratioX192 = ((10 ** token1.decimals()) << 192) / (price);
        uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(ratioX192));
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
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
        (int24 lower, int24 upper) = _getUpperAndLowerTick(IUniswapV3Pool(pool), size, 0);
        // if (lower < 0) console.log("lower (-)", uint24(-1 * lower));
        // else console.log("lower (+)", uint24(lower));
        // if (upper < 0) console.log("upper (-)", uint24(-1 * upper));
        // else console.log("upper (+)", uint24(upper));
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

    function _createBytesDataToOpenLPWithTicks(
        address pool,
        uint256 index,
        uint256 amount0,
        uint256 amount1,
        int24 lower,
        int24 upper
    ) internal view returns (bytes memory) {
        // if (lower < 0) console.log("lower (-)", uint24(-1 * lower));
        // else console.log("lower (+)", uint24(lower));
        // if (upper < 0) console.log("upper (-)", uint24(-1 * upper));
        // else console.log("upper (+)", uint24(upper));
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
        address owner,
        uint256 index,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return
            abi.encodeWithSelector(
                SinglePositionUniswapV3Adaptor.addToPosition.selector,
                tokenId,
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
        uint256 id,
        ERC20 token0,
        ERC20 token1
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                SinglePositionUniswapV3Adaptor.removeUnOwnedPositionFromTracker.selector,
                id,
                token0,
                token1
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
