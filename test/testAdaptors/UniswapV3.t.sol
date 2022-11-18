// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, Cellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, IGravity } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
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

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

// Will test the swapping and cellar position management using adaptors
contract UniswapV3AdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MockCellar private cellar;
    MockGravity private gravity;

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;

    Registry private registry;

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

    UniswapV3Adaptor private uniswapV3Adaptor;
    ERC20Adaptor private erc20Adaptor;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

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
        uniswapV3Adaptor = new UniswapV3Adaptor();
        erc20Adaptor = new ERC20Adaptor();

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

        // priceRouter.addAsset(USDC, 0, 0, false, 0);
        // priceRouter.addAsset(DAI, 0, 0, false, 0);
        // priceRouter.addAsset(WETH, 0, 0, false, 0);

        // Cellar positions array.
        uint32[] memory positions = new uint32[](5);
        uint32[] memory debtPositions;

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(uniswapV3Adaptor), 0, 0);
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC), 0, 0);
        daiPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(DAI), 0, 0);
        wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH), 0, 0);
        usdcDaiPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(DAI, USDC), 0, 0);
        usdcWethPosition = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(USDC, WETH), 0, 0);

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
            abi.encode(positions, debtPositions, positionConfigs, debtConfigs, 0, strategist)
        );
        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Allow cellar to use CellarAdaptor so it can swap ERC20's and enter/leave other cellar positions.
        cellar.setupAdaptor(address(uniswapV3Adaptor));

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
    }

    function testOpeningAndClosingUniV3Position() external {
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
        adaptorCalls[0] = _createBytesDataToCloseLP(address(cellar), 0);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function testAddingToExistingPosition() external {
        deal(address(USDC), address(this), 201_000e6);
        cellar.deposit(201_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataForSwap(USDC, DAI, 100, 100_500e6);

        adaptorCalls[1] = _createBytesDataToOpenLP(DAI, USDC, 100, 50_000e18, 50_000e6, 10);

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddLP(address(cellar), 0, 50_000e18, 50_000e6);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
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
        adaptorCalls[0] = _createBytesDataToTakeLP(address(cellar), 0, 0.5e18);
        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
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
        uint256 deviation = cellar.allowedRebalanceDeviation();
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__TotalAssetDeviatedOutsideRange.selector,
                    0,
                    assets.mulWadDown(1e18 - deviation),
                    assets.mulWadDown(1e18 + deviation)
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

    //TODO add integration tests

    // ========================================= GRAVITY FUNCTIONS =========================================

    // Since this contract is set as the Gravity Bridge, this will be called by
    // the Cellar's `sendFees` function to send funds Cosmos.
    function sendToCosmos(
        address asset,
        bytes32,
        uint256 assets
    ) external {
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
        uint256 ratioX192 = ((10**token1.decimals()) << 192) / (price);
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
        uint256 liquidityPer
    ) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        (, , , , , , , uint128 positionLiquidity, , , , ) = positionManager.positions(tokenId);
        uint128 liquidity = uint128((positionLiquidity * liquidityPer) / 1e18);
        return abi.encodeWithSelector(UniswapV3Adaptor.takeFromPosition.selector, tokenId, liquidity, 0, 0);
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
}
