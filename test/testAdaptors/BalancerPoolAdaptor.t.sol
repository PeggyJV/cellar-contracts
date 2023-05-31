// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router2/PriceRouter.sol";
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
import { IVault } from "src/interfaces/external/Balancer/IVault.sol";
import { MockBPTPriceFeed } from "src/mocks/MockBPTPriceFeed.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import { MockBalancerPoolAdaptor } from "src/mocks/adaptors/MockBalancerPoolAdaptor.sol";

// TODO: update PriceRouter2 name to just PriceRouter and directory once we get it working and for the PR. Really it should be just in the rebase to main.
contract BalancerPoolAdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    BalancerPoolAdaptor private balancerPoolAdaptor;
    ERC20Adaptor private erc20Adaptor;
    CellarInitializableV2_2 private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;
    MockBPTPriceFeed private mockBPTETHOracle;
    MockBalancerPoolAdaptor private mockBalancerPoolAdaptor;

    uint32 private usdcPosition;
    uint32 private bbaUSDPosition;
    address private immutable strategist = vm.addr(0xBEEF);
    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    // Mainnet contracts
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Balancer specific vars
    address private constant GAUGE_B_stETH_STABLE = 0xcD4722B7c24C29e0413BDCd9e51404B4539D14aE; // Balancer B-stETH-STABLE Gauge Depo... (B-stETH-S...)
    ERC20 private BB_A_USD = ERC20(0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016);
    ERC20 private constant WstEth = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0); // TODO: Used for mock-bb-a-usd-oracle setup, delete when we integrate actual priceRouter v2 Balancer extensions.

    IVault vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerRelayer relayer = IBalancerRelayer(0xfeA793Aa415061C483D2390414275AD314B3F621);

    address private constant LIQUIDITY_GAUGE_FACTORY = 0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC; //https://etherscan.io/address/0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC#code TODO: This is the old one
    // address private constant NEWEST_LIQUIDITY_GAUGE_FACTORY = 0xf1665E19bc105BE4EDD3739F88315cC699cc5b65;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    // Balancer data to join bb-aUSD (0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016) with 100 USDC for Cellar address
    // 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c - address of the cellar
    bytes joinData =
        hex"ac9650d8000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000002042e6272ea0000000000000000000000000000000000000000000000000000000000000120000000000000000000000000A4AD4f68d0b91CFD19687c881e50f3A00242828c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f62100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006459107a0000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000004fa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000000000000000000000000000000000000000005f5e10000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003a48fe4624ffebb0bbf162e64fb9d0dfe186e517d84c395f0160000000000000000000005020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f621000000000000000000000000A4AD4f68d0b91CFD19687c881e50f3A00242828c00000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000000ba100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000040000000000000000000000006667c6fa9f2b3fc1cc8d85320b62703d938e4385000000000000000000000000a1697f9af0875b63ddc472d6eebada8c1fab8568000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f792692000000000000000000000000febb0bbf162e64fb9d0dfe186e517d84c395f016000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000005644b476ee4704a53000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba1000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000";

    // Balancer data to join bb-aUSD (0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016) with 100 USDC for testContract
    //0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 - testContract address
    bytes joinDataTestContract =
        hex"ac9650d8000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000002042e6272ea00000000000000000000000000000000000000000000000000000000000001200000000000000000000000007FA9385bE102ac3EAc297483Dd6233D62b3e14960000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f62100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006459107a0000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000004fa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000000000000000000000000000000000000000005f5e10000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003a48fe4624ffebb0bbf162e64fb9d0dfe186e517d84c395f0160000000000000000000005020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f6210000000000000000000000007FA9385bE102ac3EAc297483Dd6233D62b3e149600000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000000ba100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000040000000000000000000000006667c6fa9f2b3fc1cc8d85320b62703d938e4385000000000000000000000000a1697f9af0875b63ddc472d6eebada8c1fab8568000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f792692000000000000000000000000febb0bbf162e64fb9d0dfe186e517d84c395f016000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000005644b476ee4704a53000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba1000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000";

    modifier checkBlockNumber() {
        if (block.number < 16700000) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16700000.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        balancerPoolAdaptor = new BalancerPoolAdaptor();
        erc20Adaptor = new ERC20Adaptor();
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        registry = new Registry(address(this), address(swapRouter), address(priceRouter));
        mockBalancerPoolAdaptor = new MockBalancerPoolAdaptor();

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);
        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Set up mockBPTETHOracle
        mockBPTETHOracle = new MockBPTPriceFeed();
        price = uint256(mockBPTETHOracle.latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockBPTETHOracle));
        stor = PriceRouter.ChainlinkDerivativeStorage(90e18, 0.1e18, 0, true);
        priceRouter.addAsset(BB_A_USD, settings, abi.encode(stor), price); // Now we have a mock price for bb-a-USD BPT in ETH, where it's mocked as actually just STETH/ETH (See mock contract and notes in there).

        // TODO: when PriceRouterV2 is done: add pricing for the balancerAdaptor using it / the extensions needed

        // Setup Cellar:

        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(balancerPoolAdaptor));
        registry.trustAdaptor(address(mockBalancerPoolAdaptor));
        bbaUSDPosition = registry.trustPosition(address(balancerPoolAdaptor), abi.encode(address(BB_A_USD)));
        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(address(USDC))); // TODO: holdingPosition --> The cellar holds USDC in association to the BalancerPoolAdaptor... but that doesn't really amake sense, probably better to do something like AAVE or something as holding position.

        cellar = new CellarInitializableV2_2(registry);

        cellar.initialize(
            abi.encode(
                address(this),
                registry,
                USDC,
                "Balancer Pools Cellar",
                "BPT-CLR",
                usdcPosition,
                abi.encode(1.1e18),
                strategist
            )
        );

        cellar.addAdaptorToCatalogue(address(balancerPoolAdaptor));
        cellar.addAdaptorToCatalogue(address(erc20Adaptor));
        cellar.addAdaptorToCatalogue(address(mockBalancerPoolAdaptor));
        USDC.safeApprove(address(cellar), type(uint256).max);
        cellar.setRebalanceDeviation(0.005e18);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        // Currently tries to write a packed slot, so below call reverts.
        // stdstore.target(address(cellar)).sig(cellar.aavePool.selector).checked_write(address(pool));
    }

    // ========================================= HAPPY PATH TESTS =========================================

    function testMockPriceFeedSupport() external {
        (uint144 maxPrice, uint80 minPrice, uint24 heartbeat, bool isETH) = priceRouter.getChainlinkDerivativeStorage(
            BB_A_USD
        );

        assertTrue(isETH, "WstEth data feed should be in ETH");
        assertEq(minPrice, 0.1e18, "Should set min price");
        assertEq(maxPrice, 90e18, "Should set max price");
        assertEq(heartbeat, 1 days, "Should set heartbeat");
        assertTrue(priceRouter.isSupported(BB_A_USD), "Asset should be supported");
    }

    /**
     * @notice happy path test for useRelayer() call w/ one example of calldata, `joinData`
     */
    function testUseRelayer() external {
        if (block.number < 16990614) {
            console.log("Invalid block number use 16990614");
            return;
        }

        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // should be no USDC with this test contract
        assertEq(USDC.balanceOf(address(cellar)), assets, "Cellar should have the USDC from test contract");

        console.log(
            "CELLAR ADDRESS: %s & CELLAR USDC BALANCE & TEST CONTRACT ADDRESS: %s",
            address(cellar),
            USDC.balanceOf(address(cellar)),
            address(this)
        );

        // new below
        ERC20[] memory tokensIn = new ERC20[](1);
        uint256[] memory amountsIn = new uint256[](1);
        bytes[] memory joinDataArray = new bytes[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        tokensIn[0] = USDC;
        amountsIn[0] = assets;
        joinDataArray[0] = joinData;
        adaptorCalls[0] = _createBytesDataToJoin(tokensIn, amountsIn, BB_A_USD, joinDataArray);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // // new above

        // bytes[] memory adaptorCalls = new bytes[](1);
        // adaptorCalls[0] = joinData;

        // vm.startPrank(address(cellar));
        // USDC.approve(address(vault), assets);
        // vault.setRelayerApproval(address(cellar), address(relayer), true);

        // balancerPoolAdaptor.useRelayer2(adaptorCalls);
        // // address(relayer).functionCall(joinData); // TODO: delete this and edit the line above to use the actual function `useRelayer()`, delete `useRelayer2()` too
        // vm.stopPrank();
    }

    // ========================================= PHASE 1 - GUARD RAIL TESTS =========================================

    // TODO: Test input params used within `UseRelayer()` call other than the `encoded calldata` itself

    /**
     * @notice test that the `useRelayer()` function from `BalancerPoolAdaptor.sol` carries out delegateCalls where it receives the proper amount.
     * @dev this does not test the underlying math within a respective contract like the BalancerRelayer & BalancerVault. 
     */
    function testSlippageChecks() external {
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
            0.99e4
        );
        // Make the swap.

        adaptorCalls[0] = _createBytesDataToJoin(from, fromAmount, to, slippageSwapData);
        data[0] = Cellar.AdaptorCall({ adaptor: address(mockBalancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

    }

    /// HELPERS

    /**
     * NOTE: it would take multiple tokens and amounts in and a single bpt out
     */
    function slippageSwap(ERC20 from, ERC20 to, uint256 inAmount, uint32 slippage) public {
        if (priceRouter.isSupported(from) && priceRouter.isSupported(to)) {
            // Figure out value in, quoted in `to`.
            uint256 fullValueOut = priceRouter.getValue(from, inAmount, to);
            uint256 valueOutWithSlippage = fullValueOut.mulDivDown(slippage, 1e4);
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

        console.log("howdy");
    }

    // call balancerRelayer.selector
    function _createBytesDataToJoin(
        ERC20[] memory tokensIn,
        uint256[] memory amountsIn,
        ERC20 bptOut,
        bytes[] memory callData
    ) public view returns (bytes memory) {
        return abi.encodeWithSelector(balancerPoolAdaptor.useRelayer.selector, tokensIn, amountsIn, bptOut, callData);
    }

    // ========================================= TODO: PHASE 2 - EDGE CASE TESTS =========================================

    /// Code related to tests to be carried out in the future for next phase checking likely used scenarios of specific encoded relayer action calls


    /**
     * @notice mock multicall used in `testSlippageChecks()` since it is treating this test contract as the `BalancerRelayer` through the `MockBalancerPoolAdaptor`
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        for (uint256 i = 0; i < data.length; i++) address(this).functionDelegateCall(data[i]);
    }

    // TODO: carry out tests checking 
    // intentionally mess with the calldata input for the relayer. Have a test where you verify whether or not that works, or not.
    // ex. use wrong tokensIN (make sure it reverts), change BPTOut (should revert at slippage check)

    // add USDC to the inputTokens so it's DAI, USDC.. you add a USDC amount to the amounts [] and verify that the resulting relayer approval for USDC is zero.

    // TODO: GET VARIABLES FOR POOLS TO TEST AND WAYS TO GENERATE CALLDATA (SEE HELPERS BELOW)
    // address private constant WEIGHTED_LUSD_LQTY_WETH = 0x5512A4bbe7B3051f92324bAcF25C02also b9000c4a50; // 33LUSD-33LQTY-33WETH (33LUSD-33...)
    // Ref: https://docs.balancer.fi/reference/contracts/deployment-addresses/mainnet.html#ungrouped-active-current-contracts:~:text=LiquidityGaugeFactory%20(v2)
    // TODO: get a Boosted Weighted Pool
    // TODO: get a linear pool addresses themselves

    // TODO: EIN - I think because Balancer has multiple types of pools we need to test, we're going to have to have bespoke positions to trust and add and whatnot. So see Compound.t.sol for reference and just instantiate them all in the setup() actually. We can test the setting up of one if we really want as a test, but that should be a test captured by the Cellar functionality/unit testing.

    // PHASE 2 EDGE-CASE TESTS

    //Harvesting / Claiming Rewards tests:
    // - Check and see what happens when you pass in a non-BPT address. Does it revert, does it return an address(0)?

    // function testMultiUseRelayer() external {}

    // /**
    //  * @notice join weighted pool using single asset and relayer
    //  */
    // function testJoinWeightedPool() external {
    //     // test setup should have respective weighted pool position trusted and bpt trusted
    //     // Have other params that are part of this tests, and probably other tests, instantiated in setup() --> tokensIn, amountsIn, bptOut, address weightedPool, address CSP, address
    //     // TODO: encode bytes callData to pass through to the relayer via balancerPoolAdaptor.useRelayer(tokensIn, amountsIn, bptOut, callData);
    // }

    // /**
    //  * @notice exit weighted pool using single bpt address and relayer
    //  */
    // function testExitWeightedPool() external {}

    // /**
    //  * @notice join composable stable pool using single asset and relayer
    //  */
    // function testJoinCSP() external {}

    // /**
    //  * @notice exit composable stable pool using single bpt address and relayer
    //  */
    // function testExitCSP() external {}

    // /**
    //  * @notice join Linear Pool using single asset and relayer
    //  * @dev joining linear pools actually uses `swaps` - see balancer docs, kept name as join for ease of understanding
    //  */
    // function testJoinLinearPool() external {}

    // /**
    //  * @notice exit Linear Pool using single asset and relayer
    //  * @dev exiting linear pools actually uses `swaps` - see balancer docs, kept name as exit for ease of understanding
    //  */
    // function testExitLinearPools() external {}

    // /**
    //  * @notice join Boosted CSP (like AAVE bb-a-USD)
    //  * @dev working with boosted pools with the relayer requires sequences of swaps and join/exit
    //  */
    // function testJoinBoostedCSP() external {}

    // /**
    //  * @notice exit Boosted CSP (like AAVE bb-a-USD)
    //  * @dev working with boosted pools with the relayer requires sequences of swaps and join/exit
    //  */
    // function testExitBoostedCSP() external {}

    // ========================================= PHASE 2: EDGE-CASE HELPER FUNCTIONS =========================================

    // NOTE: subgraph to help find poolID for respective pools: https://thegraph.com/hosted-service/subgraph/balancer-labs/balancer-v2

    // /**
    //  * @notice helper to create bytes for exiting a CSP
    //  */
    // // TODO: create helper functions that will feed into _createBytesDataForRelayer(). Within specific tests, these helpers will be used to create the 'sequence of actions' in a bytes[] and be passed through _createBytesDataForRelayer()
    // function _createBytesDataForRelayer(
    //     ERC20[] memory tokensIn,
    //     uint256[] memory amountsIn,
    //     ERC20 bptOut,
    //     bytes[] memory callData
    // ) internal pure returns (bytes memory) {
    //     return abi.encodeWithSelector(BalancerPoolAdaptor.useRelayer.selector, tokensIn, amountsIn, bptOut, callData);
    // }

    // /**
    //  * @notice helper to create bytes for joining a weighted pool
    //  */
    // function _createBytesDataToJoinWeightedPool() internal pure returns () {

    // }

    // /**
    //  * @notice helper to create bytes for exiting a weighted pool
    //  */
    // function _createBytesDataToExitWeightedPool() internal pure returns () {

    // }

    // /**
    //  * @notice helper to create bytes for joining a CSP
    //  * @dev actual implementation within Balancer VaultActions is that CSP will have pre-minted BPT, but it has a `joinPool()` call still that just has different implementation then typical `joinPool()` where asset balances are adjusted but no minting happens
    //  */
    // function _createBytesDataToJoinComposableStablePool() internal pure returns () {

    // }

    // /**
    //  * @notice helper to create bytes for exiting a CSP
    //  * @dev actual implementation within Balancer VaultActions is that CSP will have pre-minted BPT, but it has a `exitPool()` call still that just has different implementation then typical `exitPool()` where asset balances are adjusted but no burning happens.
    //  */
    // function _createBytesDataToExitComposableStablePool() internal pure returns () {

    // }

    // /**
    //  * @notice helper to create bytes for when swapping using linear pools
    //  */
    // function _createBytesDataToSwapUsingLinearPools() internal pure returns () {

    // }

    // /**
    //  * @notice helper to create bytes for when using generic swapping functionality of Balancer
    //  */
    // function _createBytesDataToSwapUsingBalancer() internal pure returns () {

    // }
}
