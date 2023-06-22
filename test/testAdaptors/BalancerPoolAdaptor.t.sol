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
// import { IVault } from "src/interfaces/external/Balancer/IVault.sol";
import { IVault, IAsset, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";
import { MockBPTPriceFeed } from "src/mocks/MockBPTPriceFeed.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import { MockBalancerPoolAdaptor } from "src/mocks/adaptors/MockBalancerPoolAdaptor.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";

contract BalancerPoolAdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    error BalancerPoolAdaptor___Slippage();

    BalancerPoolAdaptor private balancerPoolAdaptor;
    BalancerStablePoolExtension private balancerStablePoolExtension;
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

    // Mainnet contracts
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private BAL = ERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Balancer specific vars
    address private constant GAUGE_B_stETH_STABLE = 0xcD4722B7c24C29e0413BDCd9e51404B4539D14aE; // Balancer B-stETH-STABLE Gauge Depo... (B-stETH-S...)
    ERC20 private BB_A_USD = ERC20(0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016);
    ERC20 private vanillaUsdcDaiUsdt = ERC20(0x79c58f70905F734641735BC61e45c19dD9Ad60bC);

    ERC20 private BB_A_USD_GAUGE = ERC20(0x0052688295413b32626D226a205b95cDB337DE86); // query subgraph for gauges wrt to poolId: https://docs.balancer.fi/reference/vebal-and-gauges/gauges.html#query-gauge-by-l2-sidechain-pool:~:text=%23-,Query%20Pending%20Tokens%20for%20a%20Given%20Pool,-The%20process%20differs
    address private constant BB_A_USD_GAUGE_ADDRESS = 0x0052688295413b32626D226a205b95cDB337DE86;
    uint256 private constant BB_A_USD_DECIMALS = 18; //BB_A_USD.decimals();
    uint256 private constant BB_A_USD_GAUGE_DECIMALS = 18; //BB_A_USD_GAUGE.decimals();
    uint256 private constant USDC_DECIMALS = 6;
    uint256 private constant USDT_DECIMALS = 18;
    uint256 private constant DAI_DECIMALS = 18;

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
        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

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
        console.log("Address Cellar", address(cellar));
    }

    function testRelayerJoinPool() external checkBlockNumber {
        bytes
            memory joinData = hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000002042e6272ea0000000000000000000000000000000000000000000000000000000000000120000000000000000000000000A4AD4f68d0b91CFD19687c881e50f3A00242828c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f621000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064921fbc0000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000004fa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f79269200000000000000000000000000000000000000000000000000000000002dc6c000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003a48fe4624ffebb0bbf162e64fb9d0dfe186e517d84c395f0160000000000000000000005020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f621000000000000000000000000A4AD4f68d0b91CFD19687c881e50f3A00242828c00000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000000ba100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000040000000000000000000000006667c6fa9f2b3fc1cc8d85320b62703d938e4385000000000000000000000000a1697f9af0875b63ddc472d6eebada8c1fab8568000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f792692000000000000000000000000febb0bbf162e64fb9d0dfe186e517d84c395f016000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000002962786912d4a7d9000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba1000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000";
        bytes[] memory joinDataArray = abi.decode(joinData, (bytes[]));
        uint256 usdcAmount = 3e6;
        deal(address(USDC), address(this), usdcAmount);
        cellar.deposit(usdcAmount, address(this));

        // Have strategist join pool.
        ERC20[] memory tokensIn = new ERC20[](1);
        tokensIn[0] = USDC;

        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = usdcAmount;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataToAdjustRelayerApproval(true);
        adaptorCalls[1] = _createBytesDataToJoin(tokensIn, amountsIn, BB_A_USD, joinDataArray);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 expectedBptFromJoin = priceRouter.getValue(USDC, usdcAmount, BB_A_USD);
        assertApproxEqRel(
            BB_A_USD.balanceOf(address(cellar)),
            expectedBptFromJoin,
            0.01e18,
            "Cellar should have received expected BPT from join."
        );
    }

    // Cellar address A4AD4f68d0b91CFD19687c881e50f3A00242828c
    // Bytes data to withdraw 50 BPTs
    // At this block number 17523303
    function testRelayerExitPool() external checkBlockNumber {
        bytes
            memory exitData = hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000048000000000000000000000000000000000000000000000000000000000000006c0000000000000000000000000000000000000000000000000000000000000090000000000000000000000000000000000000000000000000000000000000003c4d80952d5febb0bbf162e64fb9d0dfe186e517d84c395f0160000000000000000000005020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000A4AD4f68d0b91CFD19687c881e50f3A00242828c000000000000000000000000fea793aa415061c483d2390414275ad314b3f62100000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000040000000000000000000000006667c6fa9f2b3fc1cc8d85320b62703d938e4385000000000000000000000000a1697f9af0875b63ddc472d6eebada8c1fab8568000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f792692000000000000000000000000febb0bbf162e64fb9d0dfe186e517d84c395f0160000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000002b5e3af16b188000000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000ba100000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001ba100000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002ba100000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002042e6272ea0000000000000000000000000000000000000000000000000000000000000120000000000000000000000000fea793aa415061c483d2390414275ad314b3f6210000000000000000000000000000000000000000000000000000000000000001000000000000000000000000A4AD4f68d0b91CFD19687c881e50f3A00242828c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000da3e439e38f3505b0000000000000000000000000000000000000000000000000000000064921a930000000000000000000000000000000000000000000000000000000000000000ba100000000000000000000000000000000000000000000000000000000000026667c6fa9f2b3fc1cc8d85320b62703d938e43850000000000000000000004fb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000006667c6fa9f2b3fc1cc8d85320b62703d938e43850000000000000000000000006b175474e89094c44da98b954eedeac495271d0fba1000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002042e6272ea0000000000000000000000000000000000000000000000000000000000000120000000000000000000000000fea793aa415061c483d2390414275ad314b3f6210000000000000000000000000000000000000000000000000000000000000001000000000000000000000000A4AD4f68d0b91CFD19687c881e50f3A00242828c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001175ed60000000000000000000000000000000000000000000000000000000064921a930000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000004a1697f9af0875b63ddc472d6eebada8c1fab85680000000000000000000004f90000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a1697f9af0875b63ddc472d6eebada8c1fab8568000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7ba1000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002042e6272ea0000000000000000000000000000000000000000000000000000000000000120000000000000000000000000fea793aa415061c483d2390414275ad314b3f6210000000000000000000000000000000000000000000000000000000000000001000000000000000000000000A4AD4f68d0b91CFD19687c881e50f3A00242828c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f08f1f0000000000000000000000000000000000000000000000000000000064921a930000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000006cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000004fa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f792692000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48ba1000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes[] memory exitDataArray = abi.decode(exitData, (bytes[]));
        uint256 bptAmount = 50e18;
        // User Joins Cellar.
        uint256 assets = 50e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar 50 Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        // Have strategist exit pool.
        ERC20[] memory tokensOut = new ERC20[](3);
        tokensOut[0] = USDC;
        tokensOut[1] = DAI;
        tokensOut[2] = USDT;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataToAdjustRelayerApproval(true);
        adaptorCalls[1] = _createBytesDataToExit(BB_A_USD, bptAmount, tokensOut, exitDataArray);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertGt(USDC.balanceOf(address(cellar)), 0, "Cellar should have received USDC.");
        assertGt(DAI.balanceOf(address(cellar)), 0, "Cellar should have received DAI.");
        assertGt(USDT.balanceOf(address(cellar)), 0, "Cellar should have received USDT.");

        uint256[] memory amountsOut = new uint256[](3);
        amountsOut[0] = USDC.balanceOf(address(cellar));
        amountsOut[1] = DAI.balanceOf(address(cellar));
        amountsOut[2] = USDT.balanceOf(address(cellar));

        uint256 valueOutInTermsOfBpt = priceRouter.getValues(tokensOut, amountsOut, BB_A_USD);
        assertApproxEqRel(
            bptAmount,
            valueOutInTermsOfBpt,
            0.01e18,
            "Cellar value out should approximately equal value in."
        );
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

    /**
     * @notice test that the `relayerJoinPool()` function from `BalancerPoolAdaptor.sol` carries out delegateCalls where it receives the proper amount.
     * @dev this does not test the underlying math within a respective contract like the BalancerRelayer & BalancerVault.
     */
    function testSlippageChecksJoinPool() external checkBlockNumber {
        // Deposit into Cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        ERC20[] memory from = new ERC20[](1);
        ERC20 to;
        uint256[] memory fromAmount = new uint256[](1);
        bytes[] memory slippageSwapData = new bytes[](1);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        // Make a swap where both assets are supported by the price router, and slippage is good.
        from[0] = USDC;
        to = BB_A_USD;
        fromAmount[0] = 1_000e6;
        slippageSwapData[0] = abi.encodeWithSignature(
            "slippageSwap(address,address,uint256,uint32)",
            from[0],
            to,
            fromAmount[0],
            0.89e4
        );
        // Make the swap.
        adaptorCalls[0] = _createBytesDataToJoin(from, fromAmount, to, slippageSwapData);
        data[0] = Cellar.AdaptorCall({ adaptor: address(mockBalancerPoolAdaptor), callData: adaptorCalls });
        vm.expectRevert((abi.encodeWithSelector(BalancerPoolAdaptor___Slippage.selector)));
        cellar.callOnAdaptor(data);
    }

    function testSlippageChecksExitPool() external checkBlockNumber {
        // Deposit into Cellar.
        uint256 assets = 1_000_000e6;
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate pool join.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        ERC20[] memory tokensOut = new ERC20[](1);
        tokensOut[0] = USDC;
        bytes[] memory slippageSwapData = new bytes[](1);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        // Make a swap where both assets are supported by the price router, and slippage is good.
        slippageSwapData[0] = abi.encodeWithSignature(
            "slippageSwap(address,address,uint256,uint32)",
            BB_A_USD,
            USDC,
            bptAmount,
            0.89e4
        );
        // Make the swap.
        adaptorCalls[0] = _createBytesDataToExit(BB_A_USD, bptAmount, tokensOut, slippageSwapData);
        data[0] = Cellar.AdaptorCall({ adaptor: address(mockBalancerPoolAdaptor), callData: adaptorCalls });
        vm.expectRevert((abi.encodeWithSelector(BalancerPoolAdaptor___Slippage.selector)));
        cellar.callOnAdaptor(data);
    }

    function testUseAdaptorToSwap() external {
        ERC20 bb_a_usdc = ERC20(0xcbFA4532D8B2ade2C261D3DD5ef2A2284f792692);
        bytes32 poolId = 0xcbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000004fa;
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: poolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(USDC)),
            assetOut: IAsset(address(bb_a_usdc)),
            amount: 100e6,
            userData: bytes(abi.encode(0))
        });

        IVault.FundManagement memory fundManagement = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        bytes memory callData = abi.encodeWithSelector(
            BalancerPoolAdaptor.swap.selector,
            singleSwap,
            fundManagement,
            0,
            block.timestamp
        );

        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(vault), 100e6);

        // IVault(vault).swap(singleSwap, fundManagement, 0, block.timestamp);
        address(balancerPoolAdaptor).functionDelegateCall(callData);

        uint256 bb_a_usdc_balance = bb_a_usdc.balanceOf(address(this));

        console.log("BPTs", bb_a_usdc_balance);

        // Now join BB_A_USD. 0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016
        poolId = 0xfebb0bbf162e64fb9d0dfe186e517d84c395f016000000000000000000000502;
        IAsset[] memory assets = new IAsset[](4);
        assets[0] = IAsset(0x6667c6fa9f2b3Fc1Cc8D85320b62703d938E4385);
        assets[1] = IAsset(0xA1697F9Af0875B63DdC472d6EeBADa8C1fAB8568);
        assets[2] = IAsset(0xcbFA4532D8B2ade2C261D3DD5ef2A2284f792692);
        assets[3] = IAsset(0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016);
        uint256[] memory maxAmountsIn = new uint256[](4);
        maxAmountsIn[0] = 0;
        maxAmountsIn[1] = 0;
        maxAmountsIn[2] = bb_a_usdc_balance;
        maxAmountsIn[3] = 0;
        bytes memory userData = abi.encode(2, 99e18, 2);
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });
        callData = abi.encodeWithSelector(
            BalancerPoolAdaptor.joinPool.selector,
            poolId,
            address(this),
            address(this),
            request
        );

        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(vault), 100e6);

        // IVault(vault).joinPool(poolId, address(this), address(this), request);
        address(balancerPoolAdaptor).functionDelegateCall(callData);

        console.log("BB_A_USD BPTs", BB_A_USD.balanceOf(address(this)));
    }

    function testJoinPool() external {
        // Deposit into Cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Have strategist rebalance into vanilla USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        ERC20[] memory assetsToApprove = new ERC20[](1);
        assetsToApprove[0] = USDC;
        uint256[] memory amountsToApprove = new uint256[](1);
        amountsToApprove[0] = assets;

        IAsset[] memory poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(DAI));
        poolAssets[1] = IAsset(address(vanillaUsdcDaiUsdt));
        poolAssets[2] = IAsset(address(USDC));
        poolAssets[3] = IAsset(address(USDT));
        uint256[] memory maxAmountsIn = new uint256[](4);
        maxAmountsIn[2] = assets;

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[1] = assets;
        bytes memory userData = abi.encode(1, amountsIn, 0);
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: poolAssets,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });
        adaptorCalls[0] = _createBytesDataToJoinPool(vanillaUsdcDaiUsdt, assetsToApprove, amountsToApprove, request);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function testUseAdaptorToJoin() external {
        bytes32 poolId = 0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7;
        IAsset[] memory assets = new IAsset[](4);
        assets[0] = IAsset(address(DAI));
        assets[1] = IAsset(address(vanillaUsdcDaiUsdt));
        assets[2] = IAsset(address(USDC));
        assets[3] = IAsset(address(USDT));
        ERC20[] memory assetsIn = new ERC20[](3);
        assetsIn[0] = DAI;
        assetsIn[1] = USDC;
        assetsIn[2] = USDT;
        uint256[] memory maxAmountsIn = new uint256[](4);
        maxAmountsIn[2] = 100e6;

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[1] = 100e6;
        bytes memory userData = abi.encode(1, amountsIn, 0);
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });
        bytes memory callData = abi.encodeWithSelector(
            BalancerPoolAdaptor.joinPool.selector,
            vanillaUsdcDaiUsdt,
            assetsIn,
            amountsIn,
            request
        );

        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(vault), 100e6);

        // IVault(vault).joinPool(poolId, address(this), address(this), request);
        address(balancerPoolAdaptor).functionDelegateCall(callData);

        console.log("BPTs", vanillaUsdcDaiUsdt.balanceOf(address(this)));
    }

    function testUseAdaptorToExit() external {
        bytes32 poolId = 0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7;
        IAsset[] memory assets = new IAsset[](4);
        assets[0] = IAsset(address(DAI));
        assets[1] = IAsset(address(vanillaUsdcDaiUsdt));
        assets[2] = IAsset(address(USDC));
        assets[3] = IAsset(address(USDT));
        uint256[] memory minAmountsOut = new uint256[](4);
        minAmountsOut[0] = 0;
        minAmountsOut[1] = 0;
        minAmountsOut[2] = 0;
        minAmountsOut[3] = 0;

        // Set user data to be EXACT_BPT_IN_FOR_TOKENS_OUT and 100e18 BPTs
        bytes memory userData = abi.encode(0, 100e18, 2);

        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: assets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        // Mint this address BPTs so we have something to redeem.
        deal(address(vanillaUsdcDaiUsdt), address(this), 100e18);

        IVault(vault).exitPool(poolId, address(this), payable(address(this)), request);
        // address(balancerPoolAdaptor).functionDelegateCall(callData);

        console.log("USDC", USDC.balanceOf(address(this)));
        console.log("DAI", DAI.balanceOf(address(this)));
        console.log("USDT", USDT.balanceOf(address(this)));
    }

    // ========================================= HELPERS =========================================

    /**
     * NOTE: it would take multiple tokens and amounts in and a single bpt out
     */
    function slippageSwap(ERC20 from, ERC20 to, uint256 inAmount, uint32 _slippage) public {
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
     * @notice create encoded bytes specifying function and params to be instantiated into the Cellar.AdaptorCall struct
     */
    function _createBytesDataToJoin(
        ERC20[] memory tokensIn,
        uint256[] memory amountsIn,
        ERC20 bptOut,
        bytes[] memory callData
    ) public view returns (bytes memory) {
        return
            abi.encodeWithSelector(balancerPoolAdaptor.relayerJoinPool.selector, tokensIn, amountsIn, bptOut, callData);
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

    /**
     * @notice create data for exiting pools using BalancerPoolAdaptor
     */
    function _createBytesDataToExit(
        ERC20 bptIn,
        uint256 amountIn,
        ERC20[] memory tokensOut,
        bytes[] memory callData
    ) public view returns (bytes memory) {
        return
            abi.encodeWithSelector(balancerPoolAdaptor.relayerExitPool.selector, bptIn, amountIn, tokensOut, callData);
    }

    function _createBytesDataToClaimRewards(address _liquidityGauge) public view returns (bytes memory) {
        return abi.encodeWithSelector(balancerPoolAdaptor.claimRewards.selector, _liquidityGauge);
    }

    function _createBytesDataToAdjustRelayerApproval(bool _change) public view returns (bytes memory) {
        return abi.encodeWithSelector(balancerPoolAdaptor.adjustRelayerApproval.selector, _change);
    }

    function _createBytesDataToJoinPool(
        ERC20 targetBpt,
        ERC20[] memory assetsIn,
        uint256[] memory amountsIn,
        IVault.JoinPoolRequest memory request
    ) public view returns (bytes memory) {
        return abi.encodeWithSelector(balancerPoolAdaptor.joinPool.selector, targetBpt, assetsIn, amountsIn, request);
    }

    function _simulatePoolJoin(address target, ERC20 tokenIn, uint256 amountIn, ERC20 bpt) internal {
        // Convert Value in to terms of bpt.
        uint256 valueInBpt = priceRouter.getValue(tokenIn, amountIn, bpt);

        // Use deal to mutate targets balances.
        uint256 tokenInBalance = tokenIn.balanceOf(target);
        deal(address(tokenIn), target, tokenInBalance - amountIn);
        uint256 bptBalance = bpt.balanceOf(target);
        deal(address(bpt), target, bptBalance + valueInBpt);
    }

    function _simulatePoolExit(address target, ERC20 bptIn, uint256 amountIn, ERC20 tokenOut) internal {
        // Convert Value in to terms of bpt.
        uint256 valueInTokenOut = priceRouter.getValue(bptIn, amountIn, tokenOut);

        // Use deal to mutate targets balances.
        uint256 bptBalance = bptIn.balanceOf(target);
        deal(address(bptIn), target, bptBalance - amountIn);
        uint256 tokenOutBalance = tokenOut.balanceOf(target);
        deal(address(tokenOut), target, tokenOutBalance + valueInTokenOut);
    }

    function _simulateBptStake(address target, ERC20 bpt, uint256 amountIn, ERC20 gauge) internal {
        // Use deal to mutate targets balances.
        uint256 tokenInBalance = bpt.balanceOf(target);
        deal(address(bpt), target, tokenInBalance - amountIn);
        uint256 gaugeBalance = gauge.balanceOf(target);
        deal(address(gauge), target, gaugeBalance + amountIn);
    }

    function _simulateBptUnStake(address target, ERC20 bpt, uint256 amountOut, ERC20 gauge) internal {
        // Use deal to mutate targets balances.
        uint256 bptBalance = bpt.balanceOf(target);
        deal(address(bpt), target, bptBalance + amountOut);
        uint256 gaugeBalance = gauge.balanceOf(target);
        deal(address(gauge), target, gaugeBalance - amountOut);
    }
}
