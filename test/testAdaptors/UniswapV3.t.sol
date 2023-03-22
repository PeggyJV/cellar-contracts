// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, Cellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, IGravity } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { MockUniswapV3Adaptor } from "src/mocks/adaptors/MockUniswapV3Adaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { LockedERC4626 } from "src/mocks/LockedERC4626.sol";
import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import "@uniswapV3C/libraries/FixedPoint128.sol";
import "@uniswapV3C/libraries/FullMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

// Will test the swapping and cellar position management using adaptors
contract UniswapV3AdaptorTest is Test, ERC721Holder {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    MockCellar private cellar;
    MockGravity private gravity;

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;

    Registry public registry;

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IUniswapV3Factory internal factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    ERC20 private LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    address private immutable strategist = vm.addr(0xBEEF);

    address private immutable cosmos = vm.addr(0xCAAA);

    MockUniswapV3Adaptor private uniswapV3Adaptor;
    ERC20Adaptor private erc20Adaptor;
    UniswapV3PositionTracker private tracker;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

    uint32 private usdcPosition;
    uint32 private wethPosition;
    uint32 private daiPosition;
    uint32 private usdcDaiPosition;
    uint32 private usdcWethPosition;

    function setUp() external {
        // Setup Registry and modules:
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        gravity = new MockGravity();
        uniswapV3Adaptor = new MockUniswapV3Adaptor();
        erc20Adaptor = new ERC20Adaptor();
        tracker = new UniswapV3PositionTracker(positionManager);

        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
        );

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

        // Cellar positions array.
        uint32[] memory positions = new uint32[](5);
        uint32[] memory debtPositions;

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(uniswapV3Adaptor));
        registry.trustAdaptor(address(erc20Adaptor));

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        daiPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(DAI));
        wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        usdcDaiPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(DAI, USDC));
        usdcWethPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(USDC, WETH));

        positions[0] = usdcPosition;
        positions[1] = daiPosition;
        positions[2] = wethPosition;
        positions[3] = usdcDaiPosition;
        positions[4] = usdcWethPosition;

        bytes[] memory positionConfigs = new bytes[](5);
        bytes[] memory debtConfigs;

        cellar = new MockCellar(
            registry,
            USDC,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            abi.encode(positions, debtPositions, positionConfigs, debtConfigs, usdcPosition, strategist)
        );
        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Allow cellar to use CellarAdaptor so it can swap ERC20's and enter/leave other cellar positions.
        cellar.addAdaptorToCatalogue(address(uniswapV3Adaptor));

        cellar.setRebalanceDeviation(0.003e18);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    // ========================================== POSITION MANAGEMENT TEST ==========================================
    function testOpenUSDC_DAIPosition() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 50_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 10);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256[] memory positions = tracker.getTokens(address(cellar), DAI, USDC);

        assertEq(positions.length, 1, "Tracker should only have 1 position.");
        assertEq(
            positions[0],
            positionManager.tokenOfOwnerByIndex(address(cellar), 0),
            "Tracker should be tracking cellars first Uni NFT."
        );
    }

    function testOpenUSDC_WETHPosition() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        uint24 fee = 500;
        adaptorCalls[0] = _createBytesDataForSwap(USDC, WETH, fee, 50_500e6);
        uint256 wethOut = priceRouter.getValue(USDC, 50_000e6, WETH);
        adaptorCalls[1] = _createBytesDataToOpenLP(USDC, WETH, fee, 50_000e6, wethOut, 222);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256[] memory positions = tracker.getTokens(address(cellar), USDC, WETH);

        assertEq(positions.length, 1, "Tracker should only have 1 position.");
        assertEq(
            positions[0],
            positionManager.tokenOfOwnerByIndex(address(cellar), 0),
            "Tracker should be tracking cellars first Uni NFT."
        );
    }

    function testOpeningAndClosingUniV3Position() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 50_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToCloseLP(address(cellar), 0);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256[] memory positions = tracker.getTokens(address(cellar), DAI, USDC);
        assertEq(positions.length, 0, "Tracker should have zero positions.");
    }

    function testAddingToExistingPosition() external {
        deal(address(USDC), address(this), 201_000e6);
        cellar.deposit(201_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 100_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 100_000);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256[] memory positions = tracker.getTokens(address(cellar), DAI, USDC);

        assertEq(positions.length, 1, "Tracker should only have 1 position.");
        assertEq(
            positions[0],
            positionManager.tokenOfOwnerByIndex(address(cellar), 0),
            "Tracker should be tracking cellars first Uni NFT."
        );

        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddLP(address(cellar), 0, 50_000e18, 50_000e6);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        positions = tracker.getTokens(address(cellar), DAI, USDC);

        assertEq(positions.length, 1, "Tracker should only have 1 position.");
    }

    function testTakingFromExistingPosition() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 50_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 10);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToTakeLP(address(cellar), 0, 0.5e18, true);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256[] memory positions = tracker.getTokens(address(cellar), DAI, USDC);

        assertEq(positions.length, 1, "Tracker should not have removed the position.");
    }

    function testTakingFees() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Add liquidity to low liquidity DAI/USDC 0.3% fee pool.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 50_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 3000, 50_000e18, 50_000e6, 100);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Have Cellar make several terrible swaps
        cellar.setRebalanceDeviation(0.1e18);
        deal(address(USDC), address(cellar), 1_000_000e6);
        deal(address(DAI), address(cellar), 1_000_000e18);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 3000, 10_000e6);
        adaptorCalls[1] = _createBytesDataForSwap(DAI, USDC, 3000, 10_000e18);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Check that cellar did receive some fees.
        deal(address(USDC), address(cellar), 1_000_000e6);
        deal(address(DAI), address(cellar), 1_000_000e18);
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToCollectFees(address(cellar), 0, type(uint128).max, type(uint128).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertTrue(USDC.balanceOf(address(cellar)) > 1_000_000e6, "Cellar should have earned USDC fees.");
        assertTrue(DAI.balanceOf(address(cellar)) > 1_000_000e18, "Cellar should have earned DAI fees.");
    }

    function testRangeOrders() external {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToOpenRangeOrder(DAI, USDC, 100, 0, assets);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(USDC.balanceOf(address(cellar)), 0, "Cellar should have put all USDC in a UniV3 range order.");
    }

    function testCellarWithSmorgasbordOfUniV3Positions() external {
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use `callOnAdaptor` to swap and enter 6 different UniV3 positions.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](8);

        adaptorCalls[0] = _createBytesDataForSwap(USDC, WETH, 500, assets / 4);
        adaptorCalls[1] = _createBytesDataForSwap(USDC, DAI, 100, assets / 4);

        adaptorCalls[2] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 30);
        adaptorCalls[3] = _createBytesDataToOpenLP(DAI, USDC, 500, 50_000e18, 50_000e6, 40);
        adaptorCalls[4] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 100);

        adaptorCalls[5] = _createBytesDataToOpenLP(USDC, WETH, 500, 50_000e6, 36e18, 20);
        adaptorCalls[6] = _createBytesDataToOpenLP(USDC, WETH, 3000, 50_000e6, 36e18, 18);
        adaptorCalls[7] = _createBytesDataToOpenLP(USDC, WETH, 500, 50_000e6, 36e18, 200);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256[] memory positions = tracker.getTokens(address(cellar), DAI, USDC);

        assertEq(positions.length, 3, "Tracker should have 3 DAI USDC positions.");
        for (uint256 i; i < 3; ++i) {
            assertEq(
                positions[i],
                positionManager.tokenOfOwnerByIndex(address(cellar), i),
                "Tracker should be tracking cellars ith Uni NFT."
            );
        }

        positions = tracker.getTokens(address(cellar), USDC, WETH);

        assertEq(positions.length, 3, "Tracker should have 3 USDC WETH positions.");
        for (uint256 i; i < 3; ++i) {
            assertEq(
                positions[i],
                positionManager.tokenOfOwnerByIndex(address(cellar), i + 3),
                "Tracker should be tracking cellars ith Uni NFT."
            );
        }
    }

    function testIsDebtReturnsFalse() external {
        assertTrue(!uniswapV3Adaptor.isDebt(), "Adaptor does not report debt.");
    }

    function testHandlingUnusedApprovals() external {
        // Open a position, but manipulate state so that router does not use full allowance
        uint256 assets = 200_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a swap by setting Cellar USDC and DAI balances.
        deal(address(USDC), address(cellar), 100_000e6);
        deal(address(DAI), address(cellar), 100_000e18);

        // Use `callOnAdaptor` to swap and enter 6 different UniV3 positions.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        adaptorCalls[0] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 30);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertTrue(
            USDC.balanceOf(address(cellar)) > 50_000e6 || DAI.balanceOf(address(cellar)) > 50_000e18,
            "One of that assets should not have been fully used."
        );

        // Make sure that approvals are zero.
        assertEq(USDC.allowance(address(cellar), address(positionManager)), 0, "USDC allowance should be zero.");
        assertEq(DAI.allowance(address(cellar), address(positionManager)), 0, "DAI allowance should be zero.");

        // Set balances to 50k each.
        deal(address(USDC), address(cellar), 50_000e6);
        deal(address(DAI), address(cellar), 50_000e18);

        // Make sure addToPosition revokes unused approvals.
        adaptorCalls[0] = _createBytesDataToAddLP(address(cellar), 0, 50_000e18, 50_000e6);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertTrue(
            USDC.balanceOf(address(cellar)) > 0 || DAI.balanceOf(address(cellar)) > 0,
            "One of that assets should not have been fully used."
        );

        // Make sure that approvals are zero.
        assertEq(USDC.allowance(address(cellar), address(positionManager)), 0, "USDC allowance should be zero.");
        assertEq(DAI.allowance(address(cellar), address(positionManager)), 0, "DAI allowance should be zero.");

        // Simulate some edge case scenario happens where there is an unused approval.
        vm.startPrank(address(cellar));
        USDC.approve(address(positionManager), 1);
        DAI.approve(address(positionManager), 1);
        vm.stopPrank();

        // Confirm approvals are non zero.
        assertEq(USDC.allowance(address(cellar), address(positionManager)), 1, "USDC allowance should be one.");
        assertEq(DAI.allowance(address(cellar), address(positionManager)), 1, "DAI allowance should be one.");

        // Strategist can manually revoke approval.
        bytes[] memory adaptorCallsToRevoke = new bytes[](2);

        adaptorCallsToRevoke[0] = abi.encodeWithSelector(
            BaseAdaptor.revokeApproval.selector,
            USDC,
            address(positionManager)
        );
        adaptorCallsToRevoke[1] = abi.encodeWithSelector(
            BaseAdaptor.revokeApproval.selector,
            DAI,
            address(positionManager)
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCallsToRevoke });
        cellar.callOnAdaptor(data);

        // Make sure that approvals are zero.
        assertEq(USDC.allowance(address(cellar), address(positionManager)), 0, "USDC allowance should be zero.");
        assertEq(DAI.allowance(address(cellar), address(positionManager)), 0, "DAI allowance should be zero.");
    }

    function testPositionBurning() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Add liquidity to low liquidity DAI/USDC 0.3% fee pool.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 50_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 3000, 50_000e18, 50_000e6, 100);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Have Cellar make several terrible swaps
        cellar.setRebalanceDeviation(0.1e18);
        deal(address(USDC), address(cellar), 1_000_000e6);
        deal(address(DAI), address(cellar), 1_000_000e18);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 3000, 10_000e6);
        adaptorCalls[1] = _createBytesDataForSwap(DAI, USDC, 3000, 10_000e18);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // First try to get rid of a token with liquidity + fees
        // Prank cellar, and give tacker approval to spend token with liquidity + fees
        uint256 positionId = positionManager.tokenOfOwnerByIndex(address(cellar), 0);
        vm.startPrank(address(cellar));
        positionManager.approve(address(tracker), positionId);
        vm.expectRevert(bytes("Not cleared"));
        tracker.removePositionFromArray(positionId, DAI, USDC);
        vm.stopPrank();

        // Remove liquidity from position but do not take fees.
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToTakeLP(address(cellar), 0, type(uint128).max, false);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Then try to get rid of a token with fees
        vm.startPrank(address(cellar));
        positionManager.approve(address(tracker), positionId);
        vm.expectRevert(bytes("Not cleared"));
        tracker.removePositionFromArray(positionId, DAI, USDC);
        vm.stopPrank();

        // Set cellar balance to 1M so we can check if fees were taken.
        deal(address(USDC), address(cellar), 1_000_000e6);
        deal(address(DAI), address(cellar), 1_000_000e18);
        // Finally collect fees and purge unused token.
        adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataToCollectFees(address(cellar), 0, type(uint128).max, type(uint128).max);
        adaptorCalls[1] = _createBytesDataToPurgePosition(address(cellar), 0);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256[] memory positions = tracker.getTokens(address(cellar), DAI, USDC);

        assertEq(positions.length, 0, "Tracker should have zero positions.");

        assertTrue(USDC.balanceOf(address(cellar)) > 1_000_000e6, "Cellar should have earned USDC fees.");
        assertTrue(DAI.balanceOf(address(cellar)) > 1_000_000e18, "Cellar should have earned DAI fees.");
    }

    // ========================================== REVERT TEST ==========================================
    function testUsingUntrackedLPPosition() external {
        // Remove USDC WETH LP position from cellar.
        cellar.removePosition(4, false);

        // Strategist tries to move funds into USDC WETH LP position.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use `callOnAdaptor` to enter a range order worth `assets` USDC.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        uint24 fee = 500;
        adaptorCalls[0] = _createBytesDataToOpenRangeOrder(USDC, WETH, fee, assets, 0);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    UniswapV3Adaptor.UniswapV3Adaptor__UntrackedLiquidity.selector,
                    address(USDC),
                    address(WETH)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testUserDepositAndWithdrawRevert() external {
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserDepositsNotAllowed.selector)));
        uniswapV3Adaptor.deposit(0, abi.encode(0), abi.encode(0));

        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        uniswapV3Adaptor.withdraw(0, address(0), abi.encode(0), abi.encode(0));
    }

    function testWithdrawableFromReturnsZero() external {
        assertEq(
            uniswapV3Adaptor.withdrawableFrom(abi.encode(0), abi.encode(0)),
            0,
            "`withdrawableFrom` should return 0."
        );
    }

    function testAddingPositionWithUnsupportedToken0Reverts() external {
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(WBTC)))
        );
        registry.trustPosition(address(uniswapV3Adaptor), abi.encode(WBTC, USDT));
    }

    function testAddingPositionWithUnsupportedToken1Reverts() external {
        // Add WBTC as a supported asset.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);
        // TX still reverts because USDT is not set up.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(USDT)))
        );
        registry.trustPosition(address(uniswapV3Adaptor), abi.encode(WBTC, USDT));
    }

    function testUsingLPTokensNotOwnedByCellarOrTokensThatDoNotExist() external {
        deal(address(USDC), address(cellar), 100_000e6);
        deal(address(DAI), address(cellar), 100_000e6);

        uint256 tokenId = 100;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Strategist first tries to add funds to a NFT the cellar does not own.
        {
            adaptorCalls[0] = abi.encodeWithSelector(
                UniswapV3Adaptor.addToPosition.selector,
                tokenId,
                type(uint256).max,
                type(uint256).max,
                0,
                0
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
            vm.expectRevert(
                bytes(abi.encodeWithSelector(UniswapV3Adaptor.UniswapV3Adaptor__NotTheOwner.selector, tokenId))
            );
            cellar.callOnAdaptor(data);
        }

        // Strategist tries to add funds to a NFT that does not exist.
        tokenId = type(uint256).max;
        {
            adaptorCalls[0] = abi.encodeWithSelector(
                UniswapV3Adaptor.addToPosition.selector,
                tokenId,
                type(uint256).max,
                type(uint256).max,
                0,
                0
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
            vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
            cellar.callOnAdaptor(data);
        }
    }

    // ========================================== INTEGRATION TEST ==========================================
    /**
     * @notice Used to check if fees are being collected.
     */
    event Collect(uint256 indexed tokenId, address recipient, uint256 amount0, uint256 amount1);

    function testIntegration() external {
        // Have whale join the cellar with 10M USDC.
        uint256 assets = 10_000_000e6;
        address whale = vm.addr(777);
        deal(address(USDC), whale, assets);
        vm.startPrank(whale);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, whale);
        vm.stopPrank();

        // Strategist manages cellar in order to achieve the following portfolio.
        // ~40% in USDC.
        // ~30% Uniswap V3 USDC/WETH 0.05%, 0.3%, and 1% LP
        // ~30% Uniswap V3 DAI/USDC 0.01% and 0.05% LP

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Create data to add liquidity to Uniswap V3.
        {
            bytes[] memory adaptorCalls = new bytes[](7);
            uint256 usdcToUse = assets.mulDivDown(15, 100);

            adaptorCalls[0] = _createBytesDataForSwap(USDC, WETH, 500, usdcToUse);
            adaptorCalls[1] = _createBytesDataForSwap(USDC, DAI, 100, usdcToUse);

            // Since we are dividing the USDC into 2 LP positions each, cut it in half.
            usdcToUse = usdcToUse / 2;

            adaptorCalls[2] = _createBytesDataToOpenLP(USDC, WETH, 500, usdcToUse, type(uint256).max, 20);
            adaptorCalls[3] = _createBytesDataToOpenLP(USDC, WETH, 3000, usdcToUse, type(uint256).max, 80);
            adaptorCalls[4] = _createBytesDataToOpenLP(USDC, WETH, 10000, usdcToUse, type(uint256).max, 10);

            adaptorCalls[5] = _createBytesDataToOpenLP(DAI, USDC, 100, type(uint256).max, usdcToUse, 30);
            adaptorCalls[6] = _createBytesDataToOpenLP(DAI, USDC, 500, type(uint256).max, usdcToUse, 40);

            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Strategist opens more Uniswap V3 positions.
        // Create data to add more liquidity to Uniswap V3.
        {
            bytes[] memory adaptorCalls = new bytes[](7);
            uint256 usdcToUse = assets.mulDivDown(6, 1000);

            adaptorCalls[0] = _createBytesDataForSwap(USDC, WETH, 500, usdcToUse);
            adaptorCalls[1] = _createBytesDataForSwap(USDC, DAI, 100, usdcToUse);

            // Since we are dividing the USDC into 2 LP positions each, cut it in half.
            usdcToUse = usdcToUse / 2;

            adaptorCalls[2] = _createBytesDataToOpenLP(USDC, WETH, 500, usdcToUse, type(uint256).max, 120);
            adaptorCalls[3] = _createBytesDataToOpenLP(USDC, WETH, 3000, usdcToUse, type(uint256).max, 44);
            adaptorCalls[4] = _createBytesDataToOpenLP(USDC, WETH, 10000, usdcToUse, type(uint256).max, 8);

            adaptorCalls[5] = _createBytesDataToOpenLP(DAI, USDC, 100, type(uint256).max, usdcToUse, 32);
            adaptorCalls[6] = _createBytesDataToOpenLP(DAI, USDC, 500, type(uint256).max, usdcToUse, 72);

            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Have test contract perform a ton of swaps in Uniswap V3 DAI/USDC and USDC/WETH pools.
        {
            uint256 assetsToSwap = 1_000_000e6;
            deal(address(USDC), address(this), assetsToSwap);
            address[] memory path0 = new address[](2);
            path0[0] = address(USDC);
            path0[1] = address(DAI);
            address[] memory path1 = new address[](2);
            path1[0] = address(USDC);
            path1[1] = address(WETH);
            address[] memory path2 = new address[](2);
            path2[0] = address(DAI);
            path2[1] = address(USDC);
            address[] memory path3 = new address[](2);
            path3[0] = address(WETH);
            path3[1] = address(USDC);
            bytes memory swapData;
            uint24[] memory poolFees_100 = new uint24[](1);
            poolFees_100[0] = 100;
            uint24[] memory poolFees_500 = new uint24[](1);
            poolFees_500[0] = 500;
            uint24[] memory poolFees_3000 = new uint24[](1);
            poolFees_3000[0] = 3000;
            uint24[] memory poolFees_10000 = new uint24[](1);
            poolFees_10000[0] = 10000;

            USDC.safeApprove(address(swapRouter), type(uint256).max);
            DAI.safeApprove(address(swapRouter), type(uint256).max);
            WETH.safeApprove(address(swapRouter), type(uint256).max);
            for (uint256 i = 0; i < 10; i++) {
                uint256 swapAmount = assetsToSwap / 2;
                swapData = abi.encode(path0, poolFees_100, swapAmount, 0);
                uint256 daiAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, DAI);
                swapData = abi.encode(path1, poolFees_500, swapAmount, 0);
                uint256 wethAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, WETH);
                swapData = abi.encode(path2, poolFees_100, daiAmount, 0);
                assetsToSwap = swapRouter.swapWithUniV3(swapData, address(this), DAI, USDC);
                swapData = abi.encode(path3, poolFees_500, wethAmount, 0);
                assetsToSwap += swapRouter.swapWithUniV3(swapData, address(this), WETH, USDC);

                swapAmount = assetsToSwap / 2;
                swapData = abi.encode(path0, poolFees_500, swapAmount, 0);
                daiAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, DAI);
                swapData = abi.encode(path1, poolFees_3000, swapAmount, 0);
                wethAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, WETH);
                swapData = abi.encode(path2, poolFees_500, daiAmount, 0);
                assetsToSwap = swapRouter.swapWithUniV3(swapData, address(this), DAI, USDC);
                swapData = abi.encode(path3, poolFees_3000, wethAmount, 0);
                assetsToSwap += swapRouter.swapWithUniV3(swapData, address(this), WETH, USDC);

                swapAmount = assetsToSwap;
                swapData = abi.encode(path1, poolFees_10000, swapAmount, 0);
                wethAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, WETH);
                swapData = abi.encode(path3, poolFees_10000, wethAmount, 0);
                assetsToSwap = swapRouter.swapWithUniV3(swapData, address(this), WETH, USDC);
            }
        }

        {
            bytes[] memory adaptorCalls = new bytes[](10);

            // Collect fees from LP tokens 0, 1, 2.
            adaptorCalls[0] = _createBytesDataToCollectFees(address(cellar), 0, type(uint128).max, type(uint128).max);
            adaptorCalls[1] = _createBytesDataToCollectFees(address(cellar), 1, type(uint128).max, type(uint128).max);
            adaptorCalls[2] = _createBytesDataToCollectFees(address(cellar), 2, type(uint128).max, type(uint128).max);

            // Take varying amounts of liquidity from tokens 3, 4, 5 using takeFromPosition.
            adaptorCalls[3] = _createBytesDataToTakeLP(address(cellar), 3, 1e18, true);
            adaptorCalls[4] = _createBytesDataToTakeLP(address(cellar), 4, 0.75e18, true);
            adaptorCalls[5] = _createBytesDataToTakeLP(address(cellar), 5, 0.5e18, true);

            //// Take all liquidity from tokens 6, 7, 8, 9 using closePosition.
            adaptorCalls[6] = _createBytesDataToCloseLP(address(cellar), 6);
            adaptorCalls[7] = _createBytesDataToCloseLP(address(cellar), 7);
            adaptorCalls[8] = _createBytesDataToCloseLP(address(cellar), 8);
            adaptorCalls[9] = _createBytesDataToCloseLP(address(cellar), 9);

            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }

        // Change rebalance deviation, so the rebalance check passes. Normally any yield would be sent to a vesting contract,
        // but for simplicity this test is not doing that.
        cellar.setRebalanceDeviation(0.01e18);

        // Check that all Cellar NFT positions have their Fees Collected by checking emitted Collect events.
        uint256[] memory nfts = new uint256[](10);
        for (uint8 i; i < 10; i++) {
            nfts[i] = positionManager.tokenOfOwnerByIndex(address(cellar), i);
            vm.expectEmit(true, true, false, false, address(positionManager));
            emit Collect(nfts[i], address(cellar), 0, 0);
        }
        cellar.callOnAdaptor(data);

        // Check that closePosition positions NFT are burned.
        for (uint8 i = 6; i < 10; i++) {
            vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
            positionManager.ownerOf(nfts[i]);
        }

        // New User deposits more funds.
        assets = 100_000e6;
        address user = vm.addr(7777);
        deal(address(USDC), user, assets);
        vm.startPrank(user);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        vm.stopPrank();

        // Add to some LP positions.
        {
            bytes[] memory adaptorCalls = new bytes[](5);
            uint256 usdcToUse = assets.mulDivDown(25, 100);

            adaptorCalls[0] = _createBytesDataForSwap(USDC, WETH, 500, usdcToUse);
            adaptorCalls[1] = _createBytesDataForSwap(USDC, DAI, 100, usdcToUse);

            // Since we are dividing the USDC into 2 LP positions each, cut it in half.
            usdcToUse = usdcToUse / 2;

            // Add liquidity to DAI/USDC positions.
            adaptorCalls[2] = _createBytesDataToAddLP(address(cellar), 3, type(uint256).max, usdcToUse);
            adaptorCalls[3] = _createBytesDataToAddLP(address(cellar), 4, type(uint256).max, usdcToUse);

            // Add liquidity to USDC/WETH position.
            adaptorCalls[4] = _createBytesDataToAddLP(address(cellar), 4, 2 * usdcToUse, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Run another round of swaps to generate fees.
        // Have test contract perform a ton of swaps in Uniswap V3 DAI/USDC and USDC/WETH pools.
        {
            uint256 assetsToSwap = 1_000_000e6;
            deal(address(USDC), address(this), assetsToSwap);
            address[] memory path0 = new address[](2);
            path0[0] = address(USDC);
            path0[1] = address(DAI);
            address[] memory path1 = new address[](2);
            path1[0] = address(USDC);
            path1[1] = address(WETH);
            address[] memory path2 = new address[](2);
            path2[0] = address(DAI);
            path2[1] = address(USDC);
            address[] memory path3 = new address[](2);
            path3[0] = address(WETH);
            path3[1] = address(USDC);
            bytes memory swapData;
            uint24[] memory poolFees_100 = new uint24[](1);
            poolFees_100[0] = 100;
            uint24[] memory poolFees_500 = new uint24[](1);
            poolFees_500[0] = 500;
            uint24[] memory poolFees_3000 = new uint24[](1);
            poolFees_3000[0] = 3000;
            uint24[] memory poolFees_10000 = new uint24[](1);
            poolFees_10000[0] = 10000;

            USDC.safeApprove(address(swapRouter), type(uint256).max);
            DAI.safeApprove(address(swapRouter), type(uint256).max);
            WETH.safeApprove(address(swapRouter), type(uint256).max);
            for (uint256 i = 0; i < 10; i++) {
                uint256 swapAmount = assetsToSwap / 2;
                swapData = abi.encode(path0, poolFees_100, swapAmount, 0);
                uint256 daiAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, DAI);
                swapData = abi.encode(path1, poolFees_500, swapAmount, 0);
                uint256 wethAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, WETH);
                swapData = abi.encode(path2, poolFees_100, daiAmount, 0);
                assetsToSwap = swapRouter.swapWithUniV3(swapData, address(this), DAI, USDC);
                swapData = abi.encode(path3, poolFees_500, wethAmount, 0);
                assetsToSwap += swapRouter.swapWithUniV3(swapData, address(this), WETH, USDC);

                swapAmount = assetsToSwap / 2;
                swapData = abi.encode(path0, poolFees_500, swapAmount, 0);
                daiAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, DAI);
                swapData = abi.encode(path1, poolFees_3000, swapAmount, 0);
                wethAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, WETH);
                swapData = abi.encode(path2, poolFees_500, daiAmount, 0);
                assetsToSwap = swapRouter.swapWithUniV3(swapData, address(this), DAI, USDC);
                swapData = abi.encode(path3, poolFees_3000, wethAmount, 0);
                assetsToSwap += swapRouter.swapWithUniV3(swapData, address(this), WETH, USDC);

                swapAmount = assetsToSwap;
                swapData = abi.encode(path1, poolFees_10000, swapAmount, 0);
                wethAmount = swapRouter.swapWithUniV3(swapData, address(this), USDC, WETH);
                swapData = abi.encode(path3, poolFees_10000, wethAmount, 0);
                assetsToSwap = swapRouter.swapWithUniV3(swapData, address(this), WETH, USDC);
            }
        }

        // Close all positions.
        {
            bytes[] memory adaptorCalls = new bytes[](6);

            //// Take all liquidity from tokens 0, 1, 2, 3, 4, and 5 using closePosition.
            adaptorCalls[0] = _createBytesDataToCloseLP(address(cellar), 0);
            adaptorCalls[1] = _createBytesDataToCloseLP(address(cellar), 1);
            adaptorCalls[2] = _createBytesDataToCloseLP(address(cellar), 2);
            adaptorCalls[3] = _createBytesDataToCloseLP(address(cellar), 3);
            adaptorCalls[4] = _createBytesDataToCloseLP(address(cellar), 4);
            adaptorCalls[5] = _createBytesDataToCloseLP(address(cellar), 5);

            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }

        // Check that all Cellar NFT positions have their Fees Collected by checking emitted Collect events.
        nfts = new uint256[](6);
        for (uint8 i; i < 6; i++) {
            nfts[i] = positionManager.tokenOfOwnerByIndex(address(cellar), i);
            vm.expectEmit(true, true, false, false, address(positionManager));
            emit Collect(nfts[i], address(cellar), 0, 0);
        }
        cellar.callOnAdaptor(data);
        assertEq(positionManager.balanceOf(address(cellar)), 0, "Cellar should have no more LP positions.");

        // Strategist converts DAI and WETH to USDC for easier withdraws.
        {
            bytes[] memory adaptorCalls = new bytes[](2);

            adaptorCalls[0] = _createBytesDataForSwap(DAI, USDC, 100, DAI.balanceOf(address(cellar)));
            adaptorCalls[1] = _createBytesDataForSwap(WETH, USDC, 500, WETH.balanceOf(address(cellar)));

            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Advance time so users can withdraw.
        vm.roll(block.timestamp + cellar.shareLockPeriod());

        // Have users exit the cellar.
        uint256 whaleAssetsToWithdraw = cellar.maxWithdraw(whale);
        uint256 userAssetsToWithdraw = cellar.maxWithdraw(user);
        uint256 cellarAssets = cellar.totalAssets();
        uint256 cellarLiability = whaleAssetsToWithdraw + userAssetsToWithdraw;
        assertGe(cellarAssets, cellarLiability, "Cellar Assets should be greater than or equal to its Liability.");

        vm.startPrank(whale);
        cellar.redeem(cellar.balanceOf(whale), whale, whale);
        vm.stopPrank();

        vm.startPrank(user);
        cellar.redeem(cellar.balanceOf(user), user, user);
        vm.stopPrank();
    }

    function testWorkingWithMaxNumberOfTrackedTokens() external {
        deal(address(USDC), address(this), 202_000e6);
        cellar.deposit(202_000e6, address(this));

        // Give cellar both assets so no swap is needed.
        deal(address(USDC), address(cellar), 101_000e6);
        deal(address(DAI), address(cellar), 101_000e18);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        adaptorCalls[0] = _createBytesDataToOpenLP(DAI, USDC, 100, 1_000e18, 1_000e6, 100_000);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        uint256[] memory positions;

        // Fill tracker with Max positions.
        for (uint256 i; i < tracker.MAX_HOLDINGS(); ++i) {
            cellar.callOnAdaptor(data);
            positions = tracker.getTokens(address(cellar), DAI, USDC);
            assertEq(positions.length, i + 1, "Tracker should i+1 positions.");
        }

        // Adding 1 more position should revert.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(UniswapV3PositionTracker.UniswapV3PositionTracker__MaxHoldingsExceeded.selector)
            )
        );
        cellar.callOnAdaptor(data);

        // Loop through, and remove all liquidity from positions.'
        for (uint256 i; i < tracker.MAX_HOLDINGS(); ++i) {
            adaptorCalls[0] = _createBytesDataToTakeLP(address(cellar), i, type(uint128).max, true);
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        // Try purging all positons in 1 TX and make sure gas usage is feasible
        adaptorCalls[0] = _createBytesDataToPurgeAllZeroLiquidityPosition(DAI, USDC);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        uint256 startingGas = gasleft();
        cellar.callOnAdaptor(data);
        assertLt(startingGas - gasleft(), 10_000_000, "Gas should be below 10M.");

        positions = tracker.getTokens(address(cellar), DAI, USDC);
        assertEq(positions.length, 0, "Cellar should zero DAI USDC positions.");
    }

    function testCellarPurgingSinglePositionsAndAllUnusedPositions() external {
        // create 10 posiitons in the cellar
        deal(address(USDC), address(this), 202_000e6);
        cellar.deposit(202_000e6, address(this));

        // Give cellar both assets so no swap is needed.
        deal(address(USDC), address(cellar), 101_000e6);
        deal(address(DAI), address(cellar), 101_000e18);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        adaptorCalls[0] = _createBytesDataToOpenLP(DAI, USDC, 100, 1_000e18, 1_000e6, 100_000);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        uint256[] memory positions;

        // Fill tracker with 10 positions.
        for (uint256 i; i < 10; ++i) {
            cellar.callOnAdaptor(data);
            positions = tracker.getTokens(address(cellar), DAI, USDC);
        }

        // Try purging a position that has liquidity
        adaptorCalls[0] = _createBytesDataToPurgePosition(address(cellar), 0);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    UniswapV3Adaptor.UniswapV3Adaptor__PurgingPositionWithLiquidity.selector,
                    positionManager.tokenOfOwnerByIndex(address(cellar), 0)
                )
            )
        );
        cellar.callOnAdaptor(data);

        // Call purge all and make sure nothing happens.
        adaptorCalls[0] = _createBytesDataToPurgeAllZeroLiquidityPosition(DAI, USDC);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        positions = tracker.getTokens(address(cellar), DAI, USDC);
        assertEq(positions.length, 10, "Cellar should have 10 DAI USDC positions.");

        // Remove liquidity from some positions.
        adaptorCalls = new bytes[](5);
        adaptorCalls[0] = _createBytesDataToTakeLP(address(cellar), 2, 0.5e18, true);
        adaptorCalls[1] = _createBytesDataToTakeLP(address(cellar), 7, type(uint128).max, true);
        adaptorCalls[2] = _createBytesDataToTakeLP(address(cellar), 3, 0.5e18, true);
        adaptorCalls[3] = _createBytesDataToTakeLP(address(cellar), 9, type(uint128).max, true);
        adaptorCalls[4] = _createBytesDataToTakeLP(address(cellar), 1, type(uint128).max, true);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Purge 1 Valid position.
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToPurgePosition(address(cellar), 7);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        positions = tracker.getTokens(address(cellar), DAI, USDC);
        assertEq(positions.length, 9, "Cellar should have 9 DAI USDC positions.");

        // Purge all unused positions.
        adaptorCalls[0] = _createBytesDataToPurgeAllZeroLiquidityPosition(DAI, USDC);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        positions = tracker.getTokens(address(cellar), DAI, USDC);
        assertEq(positions.length, 7, "Cellar should have 7 DAI USDC positions.");

        for (uint256 i; i < 7; ++i) {
            assertEq(
                positions[i],
                positionManager.tokenOfOwnerByIndex(address(cellar), i),
                "Tracker should be tracking cellars ith Uni NFT."
            );
        }
    }

    function testCellarAddingAndRemovingPositionReverts() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 50_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 10);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Try to have the cellar add a position it does not own.
        vm.startPrank(address(cellar));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    UniswapV3PositionTracker.UniswapV3PositionTracker__CallerDoesNotOwnTokenId.selector
                )
            )
        );
        tracker.addPositionToArray(100, USDC, DAI);
        vm.stopPrank();

        // Try to re add a position.
        uint256[] memory positions = tracker.getTokens(address(cellar), DAI, USDC);
        vm.startPrank(address(cellar));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    UniswapV3PositionTracker.UniswapV3PositionTracker__TokenIdAlreadyTracked.selector
                )
            )
        );
        tracker.addPositionToArray(positions[0], DAI, USDC);
        vm.stopPrank();

        deal(address(DAI), address(this), 50_000e18);
        deal(address(USDC), address(this), 50_000e6);
        address(uniswapV3Adaptor).functionDelegateCall(
            _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 10)
        );
        uint256 id = positionManager.tokenOfOwnerByIndex(address(this), 0);

        uint256 totalAssetsBefore = cellar.totalAssets();

        // Send token to cellar.
        positionManager.transferFrom(address(this), address(cellar), id);

        // Check totalAssets.
        assertEq(cellar.totalAssets(), totalAssetsBefore, "Total Assets should not change.");

        // First pass in incorrect underlying.
        vm.startPrank(address(cellar));
        positionManager.approve(address(tracker), id);
        vm.expectRevert(
            bytes(abi.encodeWithSelector(UniswapV3PositionTracker.UniswapV3PositionTracker__TokenIdNotFound.selector))
        );
        tracker.removePositionFromArray(id, USDC, WETH);
        vm.stopPrank();

        // Now pass in correct underlying.
        vm.startPrank(address(cellar));
        vm.expectRevert(
            bytes(abi.encodeWithSelector(UniswapV3PositionTracker.UniswapV3PositionTracker__TokenIdNotFound.selector))
        );
        tracker.removePositionFromArray(id, DAI, USDC);
        vm.stopPrank();

        // Try re-adding same position but with tokens swapped, should succeed but totalAssets should remain the same.
        vm.startPrank(address(cellar));
        tracker.addPositionToArray(positions[0], USDC, DAI);
        vm.stopPrank();

        // Check totalAssets.
        assertEq(cellar.totalAssets(), totalAssetsBefore, "Total Assets should not change.");

        // Try removing an owned postion from tracker using the remove unowned position and make sure it reverts
        vm.startPrank(address(cellar));
        vm.expectRevert(
            bytes(abi.encodeWithSelector(UniswapV3PositionTracker.UniswapV3PositionTracker__CallerOwnsTokenId.selector))
        );
        tracker.removePositionFromArrayThatIsNotOwnedByCaller(id, DAI, USDC);
        vm.stopPrank();
    }

    function testGriefingAttack() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 50_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 10);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 gas = gasleft();
        cellar.totalAssets();
        uint256 totalAssetsGasCost = gas - gasleft();

        // Send multiple uniswap V3 NFTs to cellar.
        deal(address(USDC), address(this), 50_000e6);
        deal(address(DAI), address(this), 50_000e18);
        for (uint256 i; i < 10; ++i) {
            address(uniswapV3Adaptor).functionDelegateCall(
                _createBytesDataToOpenLP(DAI, USDC, 100, 1_000e18, 1_000e6, 10)
            );
            uint256 id = positionManager.tokenOfOwnerByIndex(address(this), 0);

            // Send token to cellar.
            positionManager.transferFrom(address(this), address(cellar), id);
        }

        // Make sure totalAssets gas cost has not rose significantly.
        gas = gasleft();
        cellar.totalAssets();
        uint256 totalAssetsGasCostAfterAttack = gas - gasleft();

        assertEq(totalAssetsGasCost, totalAssetsGasCostAfterAttack, "Gas cost should be the same.");
    }

    function testIdsAreIgnoredIfNotOwnedByCellar() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](3);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 50_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 100, 25_000e18, 25_000e6, 1_000);
        adaptorCalls[2] = _createBytesDataToOpenLP(DAI, USDC, 100, 25_000e18, 25_000e6, 1_000);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Save total assets.
        uint256 totalAssetsBefore = cellar.totalAssets();

        // Now that cellar owns 2 uniswap v3 positions, spoof cellar to transfer 1 out.
        vm.startPrank(address(cellar));
        uint256 idToRemove = positionManager.tokenOfOwnerByIndex(address(cellar), 0);
        positionManager.transferFrom(address(cellar), address(this), idToRemove);
        vm.stopPrank();

        // Tracked array still returns 2 LP positions.
        uint256[] memory positions = tracker.getTokens(address(cellar), DAI, USDC);

        assertEq(positions.length, 2, "Tracker should report 2 DAI USDC LP positions.");

        // Total assets should be cut in half because the LP position the cellar does not own should not be included in totalAssets.
        assertApproxEqRel(
            cellar.totalAssets(),
            totalAssetsBefore / 2,
            0.05e18,
            "Cellar should have about half the assets."
        );

        // Strategist can remove the unowned tracked position.
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRemoveTrackedPositionNotOwned(idToRemove, DAI, USDC);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        positions = tracker.getTokens(address(cellar), DAI, USDC);

        assertEq(positions.length, 1, "Tracker should report 1 DAI USDC LP position1.");

        // Total assets should not change much.
        assertApproxEqRel(
            cellar.totalAssets(),
            totalAssetsBefore / 2,
            0.05e18,
            "Cellar should have about half the assets."
        );
    }

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
        ERC20 token0,
        ERC20 token1,
        uint24 fee,
        int24 size,
        int24 shift
    ) internal view returns (int24 lower, int24 upper) {
        uint256 price = priceRouter.getExchangeRate(token1, token0);
        uint256 ratioX192 = ((10 ** token1.decimals()) << 192) / (price);
        uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(ratioX192));
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        tick = tick + shift;

        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(address(token0), address(token1), fee));
        int24 spacing = pool.tickSpacing();
        lower = tick - (tick % spacing);
        lower = lower - ((spacing * size) / 2);
        upper = lower + spacing * size;
    }

    function _createBytesDataForSwap(
        ERC20 from,
        ERC20 to,
        uint24 poolFee,
        uint256 fromAmount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = poolFee;
        bytes memory params = abi.encode(path, poolFees, fromAmount, 0);
        return
            abi.encodeWithSelector(BaseAdaptor.swap.selector, from, to, fromAmount, SwapRouter.Exchange.UNIV3, params);
    }

    function _createBytesDataToOpenLP(
        ERC20 token0,
        ERC20 token1,
        uint24 poolFee,
        uint256 amount0,
        uint256 amount1,
        int24 size
    ) internal view returns (bytes memory) {
        (int24 lower, int24 upper) = _getUpperAndLowerTick(token0, token1, poolFee, size, 0);
        return
            abi.encodeWithSelector(
                UniswapV3Adaptor.openPosition.selector,
                token0,
                token1,
                poolFee,
                amount0,
                amount1,
                0,
                0,
                lower,
                upper
            );
    }

    function _createBytesDataToCloseLP(address owner, uint256 index) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.closePosition.selector, tokenId, 0, 0);
    }

    function _createBytesDataToAddLP(
        address owner,
        uint256 index,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.addToPosition.selector, tokenId, amount0, amount1, 0, 0);
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
        return abi.encodeWithSelector(UniswapV3Adaptor.takeFromPosition.selector, tokenId, liquidity, 0, 0, takeFees);
    }

    function _createBytesDataToCollectFees(
        address owner,
        uint256 index,
        uint128 amount0,
        uint128 amount1
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.collectFees.selector, tokenId, amount0, amount1);
    }

    function _createBytesDataToPurgePosition(address owner, uint256 index) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.purgeSinglePosition.selector, tokenId);
    }

    function _createBytesDataToPurgeAllZeroLiquidityPosition(
        ERC20 token0,
        ERC20 token1
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(UniswapV3Adaptor.purgeAllZeroLiquidityPositions.selector, token0, token1);
    }

    function _createBytesDataToRemoveTrackedPositionNotOwned(
        uint256 id,
        ERC20 token0,
        ERC20 token1
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(UniswapV3Adaptor.removeUnOwnedPositionFromTracker.selector, id, token0, token1);
    }

    function _createBytesDataToOpenRangeOrder(
        ERC20 token0,
        ERC20 token1,
        uint24 poolFee,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (bytes memory) {
        int24 lower;
        int24 upper;
        if (amount0 > 0) {
            (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, 100);
        } else {
            (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, -100);
        }

        return
            abi.encodeWithSelector(
                UniswapV3Adaptor.openPosition.selector,
                token0,
                token1,
                poolFee,
                amount0,
                amount1,
                0,
                0,
                lower,
                upper
            );
    }

    // Used to spoof adaptor into thinkig this is a cellar contract.
    function isPositionUsed(uint256) public pure returns (bool) {
        return true;
    }
}
