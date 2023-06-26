// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";
import { BalancerPoolAdaptor } from "src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol";
import { ILiquidityGaugev3Custom } from "src/interfaces/external/Balancer/ILiquidityGaugev3Custom.sol";
import { IBasePool } from "src/interfaces/external/Balancer/typically-npm/IBasePool.sol";
// import { IVault } from "src/interfaces/external/Balancer/IVault.sol";
import { IVault, IAsset, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";
import { MockBPTPriceFeed } from "src/mocks/MockBPTPriceFeed.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import { MockBalancerPoolAdaptor } from "src/mocks/adaptors/MockBalancerPoolAdaptor.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

contract BalancerPoolAdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    error BalancerPoolAdaptor___Slippage();

    BalancerPoolAdaptor private balancerPoolAdaptor;
    BalancerStablePoolExtension private balancerStablePoolExtension;
    WstEthExtension private wstethExtension;

    ERC20Adaptor private erc20Adaptor;
    CellarInitializableV2_2 private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;
    MockBPTPriceFeed private mockBPTETHOracle;
    MockBPTPriceFeed private mockStakedBPTOracle;
    MockBalancerPoolAdaptor private mockBalancerPoolAdaptor;

    uint32 private usdcPosition;
    uint32 private daiPosition;
    uint32 private usdtPosition;
    uint32 private bbaUSDPosition;
    uint32 private vanillaBbaUSDPosition;
    uint32 private bbaUSDGaugePosition;
    address private immutable strategist = vm.addr(0xBEEF);
    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant EXTENSION_DERIVATIVE = 3;
    uint32 private bbaWETHPosition;
    uint32 private waWETHPosition;
    uint32 private wstETHPosition;
    uint32 private WETHPosition;
    uint32 private wstETH_bbaWETHPosition;

    // Mainnet contracts
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private BAL = ERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    ERC20 private wstETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 private STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Balancer specific vars
    ERC20 private BB_A_USD = ERC20(0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016);
    ERC20 private vanillaUsdcDaiUsdt = ERC20(0x79c58f70905F734641735BC61e45c19dD9Ad60bC);
    ERC20 private BB_A_WETH = ERC20(0x60D604890feaa0b5460B28A424407c24fe89374a);
    ERC20 private wstETH_bbaWETH = ERC20(0xE0fCBf4d98F0aD982DB260f86cf28b49845403C5);

    // Linear Pools.
    ERC20 private bb_a_dai = ERC20(0x6667c6fa9f2b3Fc1Cc8D85320b62703d938E4385);
    ERC20 private bb_a_usdt = ERC20(0xA1697F9Af0875B63DdC472d6EeBADa8C1fAB8568);
    ERC20 private bb_a_usdc = ERC20(0xcbFA4532D8B2ade2C261D3DD5ef2A2284f792692);

    ERC20 private BB_A_USD_GAUGE = ERC20(0x0052688295413b32626D226a205b95cDB337DE86); // query subgraph for gauges wrt to poolId: https://docs.balancer.fi/reference/vebal-and-gauges/gauges.html#query-gauge-by-l2-sidechain-pool:~:text=%23-,Query%20Pending%20Tokens%20for%20a%20Given%20Pool,-The%20process%20differs
    address private constant BB_A_USD_GAUGE_ADDRESS = 0x0052688295413b32626D226a205b95cDB337DE86;
    address private constant wstETH_bbaWETH_GAUGE_ADDRESS = 0x5f838591A5A8048F0E4C4c7fCca8fD9A25BF0590;

    // Mainnet Balancer Specific Addresses
    address private vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private relayer = 0xfeA793Aa415061C483D2390414275AD314B3F621;
    address private minter = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;
    uint32 private slippage = 0.9e4;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;

    bytes private adaptorData = abi.encode(address(BB_A_USD), BB_A_USD_GAUGE_ADDRESS);

    modifier checkBlockNumber() {
        if (block.number < 17523303) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17523303.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        balancerPoolAdaptor = new BalancerPoolAdaptor(vault, relayer, minter, slippage);
        erc20Adaptor = new ERC20Adaptor();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        registry = new Registry(address(this), address(swapRouter), address(priceRouter));
        priceRouter = new PriceRouter(registry, WETH);
        wstethExtension = new WstEthExtension(priceRouter);
        registry.setAddress(2, address(priceRouter));
        balancerStablePoolExtension = new BalancerStablePoolExtension(priceRouter, IVault(vault));
        mockBalancerPoolAdaptor = new MockBalancerPoolAdaptor(address(this), address(this), minter, slippage);

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
        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        // Add wstETH pricing.
        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        // Add wstEth pricing.
        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        priceRouter.addAsset(wstETH, settings, abi.encode(0), price);

        // Add bb_a_USD pricing.
        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        ERC20[8] memory underlyings;
        underlyings[0] = USDC;
        underlyings[1] = DAI;
        underlyings[2] = USDT;
        BalancerStablePoolExtension.ExtensionStorage memory extensionStor = BalancerStablePoolExtension
            .ExtensionStorage({
                poolId: bytes32(0),
                poolDecimals: 18,
                rateProviderDecimals: rateProviderDecimals,
                rateProviders: rateProviders,
                underlyingOrConstituent: underlyings
            });

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
        priceRouter.addAsset(BB_A_USD, settings, abi.encode(extensionStor), 1e8);

        // Add vanilla USDC DAI USDT Bpt pricing.
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
        priceRouter.addAsset(vanillaUsdcDaiUsdt, settings, abi.encode(extensionStor), 1e8);

        // Setup Cellar:
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(balancerPoolAdaptor));
        registry.trustAdaptor(address(mockBalancerPoolAdaptor));

        bbaUSDPosition = registry.trustPosition(
            address(balancerPoolAdaptor),
            abi.encode(address(BB_A_USD), BB_A_USD_GAUGE_ADDRESS)
        );
        vanillaBbaUSDPosition = registry.trustPosition(
            address(balancerPoolAdaptor),
            abi.encode(address(vanillaUsdcDaiUsdt), address(0))
        );
        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(address(USDC))); // holdingPosition for tests
        daiPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(address(DAI))); // holdingPosition for tests
        usdtPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(address(USDT))); // holdingPosition for tests
        cellar = new CellarInitializableV2_2(registry);

        cellar.initialize(
            abi.encode(
                address(this),
                registry,
                USDC,
                "Balancer Pools Cellar",
                "BPT-CLR",
                usdcPosition,
                abi.encode(0),
                strategist
            )
        );

        cellar.addAdaptorToCatalogue(address(balancerPoolAdaptor));
        cellar.addAdaptorToCatalogue(address(erc20Adaptor));
        cellar.addAdaptorToCatalogue(address(mockBalancerPoolAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        cellar.setRebalanceDeviation(0.005e18);
        cellar.addPositionToCatalogue(daiPosition);
        cellar.addPositionToCatalogue(usdtPosition);
        cellar.addPositionToCatalogue(bbaUSDPosition);
        cellar.addPositionToCatalogue(vanillaBbaUSDPosition);

        cellar.addPosition(0, bbaUSDPosition, abi.encode(0), false);
        cellar.addPosition(0, vanillaBbaUSDPosition, abi.encode(0), false);
        cellar.addPosition(0, daiPosition, abi.encode(0), false);
        cellar.addPosition(0, usdtPosition, abi.encode(0), false);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        // Currently tries to write a packed slot, so below call reverts.
        // stdstore.target(address(cellar)).sig(cellar.aavePool.selector).checked_write(address(pool));
    }

    // ========================================= HAPPY PATH TESTS =========================================

    function testTotalAssets(uint256 assets) external checkBlockNumber {
        // User Joins Cellar.
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate strategist pool join.
        _simulatePoolJoin(address(cellar), USDC, assets, BB_A_USD);
        assertApproxEqAbs(cellar.totalAssets(), assets, 10, "Cellar totalAssets should approximately equal assets.");

        // Simulate strategist stakes all their BPTs.
        uint256 bbAUsdBalance = BB_A_USD.balanceOf(address(cellar));
        _simulateBptStake(address(cellar), BB_A_USD, bbAUsdBalance, BB_A_USD_GAUGE);
        assertApproxEqAbs(cellar.totalAssets(), assets, 10, "Cellar totalAssets should approximately equal assets.");

        // Simulate strategist unstaking half their BPTs.
        _simulateBptUnStake(address(cellar), BB_A_USD, bbAUsdBalance / 2, BB_A_USD_GAUGE);
        assertApproxEqAbs(cellar.totalAssets(), assets, 10, "Cellar totalAssets should approximately equal assets.");

        // Simulate strategist full unstake, and exit.
        bbAUsdBalance = BB_A_USD_GAUGE.balanceOf(address(cellar));
        _simulateBptUnStake(address(cellar), BB_A_USD, bbAUsdBalance, BB_A_USD_GAUGE);
        bbAUsdBalance = BB_A_USD.balanceOf(address(cellar));
        _simulatePoolExit(address(cellar), BB_A_USD, bbAUsdBalance, USDC);
        assertApproxEqAbs(cellar.totalAssets(), assets, 10, "Cellar totalAssets should approximately equal assets.");

        // At this point Cellar should hold approximately assets of USDC, and no bpts or guage bpts.
        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            assets,
            10,
            "Cellar should be holding assets amount of USDC."
        );
        assertEq(BB_A_USD.balanceOf(address(cellar)), 0, "Cellar should have no BB_A_USD.");
        assertEq(BB_A_USD_GAUGE.balanceOf(address(cellar)), 0, "Cellar should have no BB_A_USD_GAUGE.");
    }

    function testStakeBpt(uint256 assets) external checkBlockNumber {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToStake(address(BB_A_USD), address(BB_A_USD_GAUGE), bptAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(cellar.totalAssets(), assets, 0.01e18, "Cellar totalAssets should equal assets.");

        // Make sure cellar actually staked into gauge.
        assertEq(BB_A_USD_GAUGE.balanceOf(address(cellar)), bptAmount, "Cellar should have staked into guage.");
    }

    function testStakeUint256Max(uint256 assets) external checkBlockNumber {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToStake(address(BB_A_USD), address(BB_A_USD_GAUGE), type(uint256).max);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(cellar.totalAssets(), assets, 0.01e18, "Cellar totalAssets should equal assets.");

        // Make sure cellar actually staked into gauge.
        assertEq(BB_A_USD_GAUGE.balanceOf(address(cellar)), bptAmount, "Cellar should have staked into guage.");
    }

    function testUnstakeBpt(uint256 assets) external checkBlockNumber {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Gauge Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD_GAUGE), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToUnstake(address(BB_A_USD), address(BB_A_USD_GAUGE), bptAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(cellar.totalAssets(), assets, 0.01e18, "Cellar totalAssets should equal assets.");

        // Make sure cellar actually staked into gauge.
        assertEq(BB_A_USD.balanceOf(address(cellar)), bptAmount, "Cellar should have unstaked from guage.");
    }

    function testUnstakeUint256Max(uint256 assets) external checkBlockNumber {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Gauge Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD_GAUGE), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToUnstake(address(BB_A_USD), address(BB_A_USD_GAUGE), type(uint256).max);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(cellar.totalAssets(), assets, 0.01e18, "Cellar totalAssets should equal assets.");

        // Make sure cellar actually staked into gauge.
        assertEq(BB_A_USD.balanceOf(address(cellar)), bptAmount, "Cellar should have unstaked from guage.");
    }

    function testClaimRewards() external checkBlockNumber {
        uint256 assets = 1_000_000e6;
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToStake(address(BB_A_USD), address(BB_A_USD_GAUGE), bptAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Now that cellar is in gauge, wait for awards to accrue.
        vm.warp(block.timestamp + (1 days / 4));

        // Strategist claims rewards.
        adaptorCalls[0] = _createBytesDataToClaimRewards(address(BB_A_USD_GAUGE));

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 cellarBALBalance = BAL.balanceOf(address(cellar));

        assertGt(cellarBALBalance, 0, "Cellar should have earned BAL rewards.");
    }

    function testUserWithdrawPullFromGauge(uint256 assets, uint256 percentInGauge) external checkBlockNumber {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        percentInGauge = bound(percentInGauge, 0, 1e18);
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        uint256 amountToStakeInGauge = bptAmount.mulDivDown(percentInGauge, 1e18);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToStake(address(BB_A_USD), address(BB_A_USD_GAUGE), amountToStakeInGauge);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 amountToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertEq(BB_A_USD.balanceOf(address(this)), bptAmount, "User should have received assets out.");
    }

    /**
     * @notice check that assetsUsed() works which also checks assetOf() works
     */
    function testAssetsUsed() external checkBlockNumber {
        ERC20[] memory actualAsset = balancerPoolAdaptor.assetsUsed(adaptorData);
        address actualAssetAddress = address(actualAsset[0]);
        assertEq(actualAssetAddress, address(BB_A_USD));
    }

    function testIsDebt() external checkBlockNumber {
        bool result = balancerPoolAdaptor.isDebt();
        assertEq(result, false);
    }

    // ========================================= PHASE 1 - GUARD RAIL TESTS =========================================

    /// joinPool() tests

    function testJoinVanillaPool() external {
        // Deposit into Cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Have strategist rebalance into vanilla USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);
        swapsBeforeJoin[0].assetIn = IAsset(address(DAI));
        swapsBeforeJoin[1].assetIn = IAsset(address(USDC));
        swapsBeforeJoin[1].amount = assets;
        swapsBeforeJoin[2].assetIn = IAsset(address(USDT));

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinPool(vanillaUsdcDaiUsdt, swapsBeforeJoin, swapData, 0);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function testJoinBoostedPool() external {
        // Deposit into Cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Have strategist rebalance into boosted USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);
        swapsBeforeJoin[0].assetIn = IAsset(address(DAI));
        swapsBeforeJoin[1].assetIn = IAsset(address(USDT));

        // Create Swap Data.
        swapsBeforeJoin[2] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_usdc)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(USDC)),
            assetOut: IAsset(address(bb_a_usdc)),
            amount: assets,
            userData: bytes(abi.encode(0))
        });

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[2] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinPool(BB_A_USD, swapsBeforeJoin, swapData, 0);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    // take joinVanillaPool, have the user deposit. Deal out cellar equal parts of the constituents (USDC, USDT, DAI). Change the swap info so it's giving multi-tokens (not just one).
    // TODO: make this a fuzzing test and write out proper assertions.
    function testJoinVanillaPoolWithMultiTokens() external {
        // Deposit into Cellar.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);

        cellar.deposit(assets, address(this));

        uint256 daiAmount = priceRouter.getValue(USDC, assets / 3, DAI);
        uint256 usdtAmount = priceRouter.getValue(USDC, assets / 3, USDT);
        uint256 usdcAmount = assets / 3;

        deal(address(USDT), address(cellar), usdtAmount);
        deal(address(DAI), address(cellar), daiAmount);
        deal(address(USDC), address(cellar), usdcAmount);

        // Have strategist rebalance into vanilla USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);
        swapsBeforeJoin[0].assetIn = IAsset(address(DAI));
        swapsBeforeJoin[0].amount = daiAmount;
        swapsBeforeJoin[1].assetIn = IAsset(address(USDC));
        swapsBeforeJoin[1].amount = usdcAmount;
        swapsBeforeJoin[2].assetIn = IAsset(address(USDT));
        swapsBeforeJoin[2].amount = usdtAmount;
        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;
        adaptorCalls[0] = _createBytesDataToJoinPool(vanillaUsdcDaiUsdt, swapsBeforeJoin, swapData, 0);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = DAI;
        baseAssets[1] = USDC;
        baseAssets[2] = USDT;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = daiAmount;
        baseAmounts[1] = usdcAmount;
        baseAmounts[2] = usdtAmount;

        uint256 expectedBPT = priceRouter.getValues(baseAssets, baseAmounts, vanillaUsdcDaiUsdt);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        // carry out tx
        cellar.callOnAdaptor(data);

        assertApproxEqRel(
            vanillaUsdcDaiUsdt.balanceOf(address(cellar)),
            expectedBPT,
            0.01e18,
            "Cellar BPT balance should incur only a small amount slippage (3%)"
        );
    }

    function testJoinBoostedPoolWithMultipleTokens() external {
        // Deposit into Cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 daiAmount = priceRouter.getValue(USDC, assets / 3, DAI);
        uint256 usdtAmount = priceRouter.getValue(USDC, assets / 3, USDT);
        uint256 usdcAmount = assets / 3;

        deal(address(USDT), address(cellar), usdtAmount);
        deal(address(DAI), address(cellar), daiAmount);
        deal(address(USDC), address(cellar), usdcAmount);

        // Have strategist rebalance into boosted USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);

        swapsBeforeJoin[0] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_dai)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(DAI)),
            assetOut: IAsset(address(bb_a_dai)),
            amount: daiAmount,
            userData: bytes(abi.encode(0))
        });

        swapsBeforeJoin[1] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_usdt)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(USDT)),
            assetOut: IAsset(address(bb_a_usdt)),
            amount: usdtAmount,
            userData: bytes(abi.encode(0))
        });

        // Create Swap Data.
        swapsBeforeJoin[2] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_usdc)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(USDC)),
            assetOut: IAsset(address(bb_a_usdc)),
            amount: usdcAmount,
            userData: bytes(abi.encode(0))
        });

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinPool(BB_A_USD, swapsBeforeJoin, swapData, 0);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = DAI;
        baseAssets[1] = USDC;
        baseAssets[2] = USDT;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = daiAmount;
        baseAmounts[1] = usdcAmount;
        baseAmounts[2] = usdtAmount;

        uint256 expectedBPT = priceRouter.getValues(baseAssets, baseAmounts, vanillaUsdcDaiUsdt);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(
            BB_A_USD.balanceOf(address(cellar)),
            expectedBPT,
            0.01e18,
            "Cellar BPT balance should incur only a small amount slippage (1%)"
        );
    }

    /**
     * More complex join: deal wstETH to user and they deposit to cellar. Cellar should be dealt equal amounts of other constituent (WETH). Prepare swaps for bb-a-WETH.
     */
    function testNonStableCoinJoinMultiTokens() external {
        uint256 assets = 1000e6;

        // Add wstETH_bbaWETH pricing.
        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        ERC20[8] memory underlyings;
        underlyings[0] = WETH;
        underlyings[1] = STETH;
        BalancerStablePoolExtension.ExtensionStorage memory extensionStor = BalancerStablePoolExtension
            .ExtensionStorage({
                poolId: bytes32(0),
                poolDecimals: 18,
                rateProviderDecimals: rateProviderDecimals,
                rateProviders: rateProviders,
                underlyingOrConstituent: underlyings
            });
        PriceRouter.AssetSettings memory settings;

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
        priceRouter.addAsset(wstETH_bbaWETH, settings, abi.encode(extensionStor), 1.787e11);

        wstETH_bbaWETHPosition = registry.trustPosition(
            address(balancerPoolAdaptor),
            abi.encode(address(wstETH_bbaWETH), wstETH_bbaWETH_GAUGE_ADDRESS)
        );
        wstETHPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(address(wstETH))); // holdingPosition for tests
        WETHPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(address(WETH))); // holdingPosition for tests

        cellar.addPositionToCatalogue(wstETHPosition);
        cellar.addPositionToCatalogue(WETHPosition);
        cellar.addPositionToCatalogue(wstETH_bbaWETHPosition);

        cellar.addPosition(0, wstETHPosition, abi.encode(0), false);
        cellar.addPosition(0, WETHPosition, abi.encode(0), false);
        cellar.addPosition(0, wstETH_bbaWETHPosition, abi.encode(0), false);

        // pricing set up for BB_A_WETH. Now, we set up the adaptorCall to actually join the pool

        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH);
        uint256 wstethAmount = priceRouter.getValue(USDC, assets / 2, wstETH);

        deal(address(WETH), address(cellar), wethAmount);
        deal(address(wstETH), address(cellar), wstethAmount);
        deal(address(USDC), address(cellar), 0);

        // Have strategist rebalance into boosted USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](2);

        // NOTE: `vault.getPoolTokens(wstETH_bbaWETH)` to be - [0]: BB_A_WETH, [1]: wstETH, [2]: wstETH_bbaWETH
        swapsBeforeJoin[0] = IVault.SingleSwap({
            poolId: IBasePool(address(BB_A_WETH)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(WETH)),
            assetOut: IAsset(address(BB_A_WETH)),
            amount: wethAmount,
            userData: bytes(abi.encode(0))
        });

        swapsBeforeJoin[1].assetIn = IAsset(address(wstETH));
        swapsBeforeJoin[1].amount = wstethAmount;

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](2);
        swapData.swapDeadlines = new uint256[](2);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinPool(wstETH_bbaWETH, swapsBeforeJoin, swapData, 0);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = WETH;
        baseAssets[1] = wstETH;
        baseAssets[2] = USDC;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = wethAmount;
        baseAmounts[1] = wstethAmount;
        baseAmounts[2] = 0;
        uint256 expectedBPT = priceRouter.getValues(baseAssets, baseAmounts, wstETH_bbaWETH);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(
            wstETH_bbaWETH.balanceOf(address(cellar)),
            expectedBPT,
            0.01e18,
            "Cellar BPT balance should incur only a small amount slippage (1%)"
        );
    }

    /// exitPool() tests

    function testExitVanillaPool() external {
        // Deposit into Cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a vanilla pool deposit by minting cellar bpts.
        uint256 bptAmount = priceRouter.getValue(USDC, assets, vanillaUsdcDaiUsdt);
        deal(address(USDC), address(cellar), 0);
        deal(address(vanillaUsdcDaiUsdt), address(cellar), bptAmount);

        // Have strategist exit pool in 1 token.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // There are no swaps to be made, so just create empty arrays.
        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);

        // There are no swaps needed because we support all the assets we get from the pool.
        IVault.SingleSwap[] memory swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(DAI));
        swapsAfterExit[1].assetIn = IAsset(address(USDC));
        swapsAfterExit[2].assetIn = IAsset(address(USDT));

        // Formulate request.
        IAsset[] memory poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(DAI));
        poolAssets[1] = IAsset(address(vanillaUsdcDaiUsdt));
        poolAssets[2] = IAsset(address(USDC));
        poolAssets[3] = IAsset(address(USDT));
        uint256[] memory minAmountsOut = new uint256[](4);
        bytes memory userData = abi.encode(0, bptAmount, 1);
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitPool(vanillaUsdcDaiUsdt, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        cellar.callOnAdaptor(data);
    }

    function testExitBoostedPool() external {
        // Deposit into Cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a vanilla pool deposit by minting cellar bpts.
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        // Have strategist exit pool in 1 token.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // There are no swaps to be made, so just create empty arrays.
        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[1] = block.timestamp;

        // We need to swap any linear pool tokens for ERC20s.
        // We don't set amounts because adaptor will automatically use all the tokens we receive as the amount.
        IVault.SingleSwap[] memory swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(bb_a_dai));
        swapsAfterExit[1].assetIn = IAsset(address(bb_a_usdt));
        swapsAfterExit[1].poolId = IBasePool(address(bb_a_usdt)).getPoolId();
        swapsAfterExit[2].assetIn = IAsset(address(bb_a_usdc));
        swapsAfterExit[0].assetOut = IAsset(address(DAI));
        swapsAfterExit[1].assetOut = IAsset(address(USDT));
        swapsAfterExit[2].assetOut = IAsset(address(USDC));

        // Formulate request.
        IAsset[] memory poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(bb_a_dai));
        poolAssets[1] = IAsset(address(bb_a_usdt));
        poolAssets[2] = IAsset(address(bb_a_usdc));
        poolAssets[3] = IAsset(address(BB_A_USD));
        uint256[] memory minAmountsOut = new uint256[](4);
        bytes memory userData = abi.encode(0, bptAmount, 1);
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitPool(BB_A_USD, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        cellar.callOnAdaptor(data);
    }

    // ========================================= HELPERS =========================================

    /**
     * NOTE: it would take multiple tokens and amounts in and a single bpt out
     */
    function slippageSwap(
        ERC20 from,
        ERC20 to,
        uint256 inAmount,
        uint32 _slippage
    ) public {
        if (priceRouter.isSupported(from) && priceRouter.isSupported(to)) {
            // Figure out value in, quoted in `to`.
            uint256 fullValueOut = priceRouter.getValue(from, inAmount, to);
            uint256 valueOutWithSlippage = fullValueOut.mulDivDown(_slippage, 1e4);
            // Deal caller new balances.
            deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
            deal(address(to), msg.sender, to.balanceOf(msg.sender) + valueOutWithSlippage);
        } else {
            // Pricing is not supported, so just assume exchange rate is 1:1.
            deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
            deal(
                address(to),
                msg.sender,
                to.balanceOf(msg.sender) + inAmount.changeDecimals(from.decimals(), to.decimals())
            );
        }
    }

    /**
     * @notice mock multicall used in `testSlippageChecks()` since it is treating this test contract as the `BalancerRelayer` through the `MockBalancerPoolAdaptor`
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        for (uint256 i = 0; i < data.length; i++) address(this).functionDelegateCall(data[i]);
    }

    /**
     * @notice create data for staking using BalancerPoolAdaptor
     */
    function _createBytesDataToStake(
        address _bpt,
        address _liquidityGauge,
        uint256 _amountIn
    ) public view returns (bytes memory) {
        return abi.encodeWithSelector(balancerPoolAdaptor.stakeBPT.selector, _bpt, _liquidityGauge, _amountIn);
    }

    /**
     * @notice create data for unstaking using BalancerPoolAdaptor
     */
    function _createBytesDataToUnstake(
        address _bpt,
        address _liquidityGauge,
        uint256 _amountOut
    ) public view returns (bytes memory) {
        return abi.encodeWithSelector(balancerPoolAdaptor.unstakeBPT.selector, _bpt, _liquidityGauge, _amountOut);
    }

    function _createBytesDataToClaimRewards(address _liquidityGauge) public view returns (bytes memory) {
        return abi.encodeWithSelector(balancerPoolAdaptor.claimRewards.selector, _liquidityGauge);
    }

    function _createBytesDataToJoinPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsBeforeJoin,
        BalancerPoolAdaptor.SwapData memory swapData,
        uint256 minimumBpt
    ) public view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                balancerPoolAdaptor.joinPool.selector,
                targetBpt,
                swapsBeforeJoin,
                swapData,
                minimumBpt
            );
    }

    function _createBytesDataToExitPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsAfterExit,
        BalancerPoolAdaptor.SwapData memory swapData,
        IVault.ExitPoolRequest memory request
    ) public view returns (bytes memory) {
        return
            abi.encodeWithSelector(balancerPoolAdaptor.exitPool.selector, targetBpt, swapsAfterExit, swapData, request);
    }

    function _simulatePoolJoin(
        address target,
        ERC20 tokenIn,
        uint256 amountIn,
        ERC20 bpt
    ) internal {
        // Convert Value in to terms of bpt.
        uint256 valueInBpt = priceRouter.getValue(tokenIn, amountIn, bpt);

        // Use deal to mutate targets balances.
        uint256 tokenInBalance = tokenIn.balanceOf(target);
        deal(address(tokenIn), target, tokenInBalance - amountIn);
        uint256 bptBalance = bpt.balanceOf(target);
        deal(address(bpt), target, bptBalance + valueInBpt);
    }

    function _simulatePoolExit(
        address target,
        ERC20 bptIn,
        uint256 amountIn,
        ERC20 tokenOut
    ) internal {
        // Convert Value in to terms of bpt.
        uint256 valueInTokenOut = priceRouter.getValue(bptIn, amountIn, tokenOut);

        // Use deal to mutate targets balances.
        uint256 bptBalance = bptIn.balanceOf(target);
        deal(address(bptIn), target, bptBalance - amountIn);
        uint256 tokenOutBalance = tokenOut.balanceOf(target);
        deal(address(tokenOut), target, tokenOutBalance + valueInTokenOut);
    }

    function _simulateBptStake(
        address target,
        ERC20 bpt,
        uint256 amountIn,
        ERC20 gauge
    ) internal {
        // Use deal to mutate targets balances.
        uint256 tokenInBalance = bpt.balanceOf(target);
        deal(address(bpt), target, tokenInBalance - amountIn);
        uint256 gaugeBalance = gauge.balanceOf(target);
        deal(address(gauge), target, gaugeBalance + amountIn);
    }

    function _simulateBptUnStake(
        address target,
        ERC20 bpt,
        uint256 amountOut,
        ERC20 gauge
    ) internal {
        // Use deal to mutate targets balances.
        uint256 bptBalance = bpt.balanceOf(target);
        deal(address(bpt), target, bptBalance + amountOut);
        uint256 gaugeBalance = gauge.balanceOf(target);
        deal(address(gauge), target, gaugeBalance - amountOut);
    }

    /**
     * TODO: create helper to make joinPool tests more efficient
     */
}
