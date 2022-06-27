// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ChainlinkPriceFeedAdaptor } from "src/modules/price-router/adaptors/ChainlinkPriceFeedAdaptor.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { FeedRegistryInterface } from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

// TODO: Test exchange rate against DEX's.
// TODO: Test new price sanity checks.
contract PriceRouterTest is Test {
    using Math for uint256;

    ChainlinkPriceFeedAdaptor private immutable chainlinkAdaptor = new ChainlinkPriceFeedAdaptor();
    PriceRouter private immutable priceRouter = new PriceRouter();

    address private immutable sender = vm.addr(0xABCD);
    address private immutable receiver = vm.addr(0xBEEF);

    // Mainnet contracts:
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private constant BOND = ERC20(0x0391D2021f89DC339F60Fff84546EA23E337750f);
    FeedRegistryInterface private constant feedRegistry =
        FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);
    IUniswapV2Router private constant uniV2Router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function setUp() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        priceRouter.addAsset(WETH, ERC20(Denominations.ETH), 0, 0, 0);
        priceRouter.addAsset(WBTC, ERC20(Denominations.BTC), 0, 0, 0);
        priceRouter.addAsset(USDC, ERC20(address(0)), 0, 0, 0);
        priceRouter.addAsset(BOND, ERC20(address(0)), 0, 0, 0);
        priceRouter.addAsset(DAI, ERC20(address(0)), 0, 0, 0);
    }

    // ======================================= SWAP TESTS =======================================

    function testExchangeRate() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        uint256 exchangeRate;

        // Test exchange rates work when quote is same as base.
        exchangeRate = priceRouter.getExchangeRate(USDC, USDC);
        assertEq(exchangeRate, 1e6, "USDC -> USDC Exchange Rate Should be 1e6");

        exchangeRate = priceRouter.getExchangeRate(DAI, DAI);
        assertEq(exchangeRate, 1e18, "DAI -> DAI Exchange Rate Should be 1e18");

        exchangeRate = priceRouter.getExchangeRate(WETH, WETH);
        assertEq(exchangeRate, 1e18, "WETH -> WETH Exchange Rate Should be 1e18");

        exchangeRate = priceRouter.getExchangeRate(WBTC, WBTC);
        assertEq(exchangeRate, 1e8, "WBTC -> WBTC Exchange Rate Should be 1e8");

        exchangeRate = priceRouter.getExchangeRate(BOND, BOND); // Weird asset with an ETH price but no USD price.
        assertEq(exchangeRate, 1e18, "BOND -> BOND Exchange Rate Should be 1e18");

        // Test exchange rates.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);
        uint256[] memory amounts = uniV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(DAI, USDC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "DAI -> USDC Exchange Rate Should be 1 +- 1% USDC");

        path[0] = address(WETH);
        path[1] = address(WBTC);
        amounts = uniV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(WETH, WBTC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> WBTC Exchange Rate Should be 0.5ish +- 1% WBTC");

        path[0] = address(WETH);
        path[1] = address(USDC);
        amounts = uniV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(WETH, USDC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> USDC Exchange Rate Failure");

        path[0] = address(USDC);
        path[1] = address(BOND);
        amounts = uniV2Router.getAmountsOut(1e6, path);

        exchangeRate = priceRouter.getExchangeRate(USDC, BOND);
        assertApproxEqRel(exchangeRate, amounts[1], 0.02e18, "USDC -> BOND Exchange Rate Failure");

        ERC20[] memory baseAssets = new ERC20[](4);
        baseAssets[0] = USDC;
        baseAssets[1] = DAI;
        baseAssets[2] = WETH;
        baseAssets[3] = WBTC;

        uint256[] memory exchangeRates = priceRouter.getExchangeRates(baseAssets, WBTC);
        assertEq(exchangeRates[3], 1e8, "WBTC -> WBTC Exchange Rate Should be 1e8");
    }

    // TODO: Add test case for getting BOND price range.
    function testPriceRange() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        uint256 min;
        uint256 max;

        // Check that exchange rates work when quote == base.
        (min, max) = priceRouter.getPriceRange(USDC);
        assertEq(min, 0.01e8, "USDC Min Price Should be $0.01");
        assertEq(max, 1000e8, "USDC Max Price Should be $1000");

        (min, max) = priceRouter.getPriceRange(DAI);
        assertEq(min, 0.01e8, "DAI Min Price Should be $0.01");
        assertEq(max, 100e8, "DAI Max Price Should be $100");

        (min, max) = priceRouter.getPriceRange(WETH);
        assertEq(min, 1e8, "WETH Min Price Should be $1");
        assertEq(max, 10_000e8, "WETH Max Price Should be $10,000");

        (min, max) = priceRouter.getPriceRange(WBTC);
        assertEq(min, 10e8, "WBTC Min Price Should be $10");
        assertEq(max, 10_000_000e8, "WBTC Max Price Should be $10,000,000");

        ERC20[] memory baseAssets = new ERC20[](4);
        baseAssets[0] = USDC;
        baseAssets[1] = DAI;
        baseAssets[2] = WETH;
        baseAssets[3] = WBTC;

        (uint256[] memory mins, uint256[] memory maxes) = priceRouter.getPriceRanges(baseAssets);

        assertEq(mins[0], 0.01e8, "USDC Min Price Should be $0.01");
        assertEq(maxes[0], 1000e8, "USDC Max Price Should be $1000");
        assertEq(mins[1], 0.01e8, "DAI Min Price Should be $0.01");
        assertEq(maxes[1], 100e8, "DAI Max Price Should be $100");
        assertEq(mins[2], 1e8, "WETH Min Price Should be $1");
        assertEq(maxes[2], 10_000e8, "WETH Max Price Should be $10,000");
        assertEq(mins[3], 10e8, "WBTC Min Price Should be $10");
        assertEq(maxes[3], 10_000_000e8, "WBTC Max Price Should be $10,000,000");
    }

    function testGetValue(
        uint256 assets0,
        uint256 assets1,
        uint256 assets2
    ) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets0 = bound(assets0, 1e6, type(uint72).max);
        assets1 = bound(assets1, 1e18, type(uint112).max);
        assets2 = bound(assets2, 1e8, type(uint48).max);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = USDC;
        baseAssets[1] = BOND;
        baseAssets[2] = WBTC;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = assets0;
        amounts[1] = assets1;
        amounts[2] = assets2;

        uint256 totalValue = priceRouter.getValues(baseAssets, amounts, USDC);

        // Find the value using uniswap.

        uint256 sum = assets0; // Since the first one is USDC, no conversion is needed.

        address[] memory path = new address[](2);
        path[0] = address(BOND);
        path[1] = address(USDC);
        uint256[] memory amountsOut = uniV2Router.getAmountsOut(1e18, path);
        sum += (amountsOut[1] * assets1) / 1e18;

        path[0] = address(WBTC);
        path[1] = address(USDC);
        amountsOut = uniV2Router.getAmountsOut(1e4, path);
        sum += (amountsOut[1] * assets2) / 1e4;

        // Most tests use a 1% price difference between Chainlink and Uniswap, but WBTC value
        // derived from Uniswap is significantly off from historical values, while the value
        // calculated by the price router is much more accurate.
        assertApproxEqRel(
            totalValue,
            sum,
            0.05e18,
            "Total Value of USDC, BOND, and WBTC outside of 10% envelope with UniV2"
        );
    }
}
