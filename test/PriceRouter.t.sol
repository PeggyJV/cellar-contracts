// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ChainlinkPriceFeedAdaptor } from "src/ChainlinkPriceFeedAdaptor.sol";
import { PriceRouter } from "src/PriceRouter.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

//TODO test exchange rate against DEX's, and test new price sanity checks
contract PriceRouterTest is Test {
    using Math for uint256;

    ChainlinkPriceFeedAdaptor private chainlinkAdaptor;
    PriceRouter private priceRouter;

    uint256 private constant privateKey0 = 0xABCD;
    uint256 private constant privateKey1 = 0xBEEF;
    address private sender = vm.addr(privateKey0);
    address private reciever = vm.addr(privateKey1);

    // Mainnet contracts:
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private BOND = ERC20(0x0391D2021f89DC339F60Fff84546EA23E337750f);
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant BTC = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    FeedRegistryInterface private FeedRegistry = FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);
    IUniswapV2Router private uniV2Router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function setUp() public {
        chainlinkAdaptor = new ChainlinkPriceFeedAdaptor(FeedRegistry);
        priceRouter = new PriceRouter(FeedRegistry);

        priceRouter.addAsset(address(WETH), address(0), uint128(0), uint128(0), uint96(1 days), ETH);
        priceRouter.addAsset(address(WBTC), address(0), uint128(0), uint128(0), uint96(1 days), BTC);
        priceRouter.addAsset(address(USDC), address(0), uint128(0), uint128(0), uint96(1 days), address(0));
        priceRouter.addAsset(address(BOND), address(0), uint128(0), uint128(0), uint96(1 days), address(0));
        priceRouter.addAsset(address(DAI), address(0), uint128(0), uint128(0), uint96(1 days), address(0));
    }

    // ======================================= SWAP TESTS =======================================

    function testExchangeRate() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        uint256 exchangeRate;

        //check that exchange rates work when quote == base
        exchangeRate = priceRouter.getExchangeRate(address(USDC), address(USDC));
        assertEq(exchangeRate, 1e6, "USDC -> USDC Exchange Rate Should be 1e6");

        exchangeRate = priceRouter.getExchangeRate(address(DAI), address(DAI));
        assertEq(exchangeRate, 1e18, "DAI -> DAI Exchange Rate Should be 1e18");

        exchangeRate = priceRouter.getExchangeRate(address(WETH), address(WETH));
        assertEq(exchangeRate, 1e18, "WETH -> WETH Exchange Rate Should be 1e18");

        exchangeRate = priceRouter.getExchangeRate(address(WBTC), address(WBTC));
        assertEq(exchangeRate, 1e8, "WBTC -> WBTC Exchange Rate Should be 1e8");

        exchangeRate = priceRouter.getExchangeRate(address(BOND), address(BOND)); //weird asset with an ETH price but no USD price
        assertEq(exchangeRate, 1e18, "BOND -> BOND Exchange Rate Should be 1e18");

        //check exchange rates work
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);
        uint256[] memory amounts = uniV2Router.getAmountsOut(1e18, path); //oooooh there is a swap fee toooooo

        exchangeRate = priceRouter.getExchangeRate(address(DAI), address(USDC));
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "DAI -> USDC Exchange Rate Should be 1 +- 1% USDC");

        path[0] = address(WETH);
        path[1] = address(WBTC);
        amounts = uniV2Router.getAmountsOut(1e18, path);
        exchangeRate = priceRouter.getExchangeRate(address(WETH), address(WBTC));
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> WBTC Exchange Rate Should be 0.5ish +- 1% WBTC");

        path[0] = address(WETH);
        path[1] = address(USDC);
        amounts = uniV2Router.getAmountsOut(1e18, path);
        exchangeRate = priceRouter.getExchangeRate(address(WETH), address(USDC));
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> USDC Exchange Rate Failure");

        path[0] = address(USDC);
        path[1] = address(BOND);
        amounts = uniV2Router.getAmountsOut(1e6, path);
        exchangeRate = priceRouter.getExchangeRate(address(USDC), address(BOND));
        assertApproxEqRel(exchangeRate, amounts[1], 0.02e18, "USDC -> BOND Exchange Rate Failure");

        address[] memory baseAssets = new address[](4);
        baseAssets[0] = address(USDC);
        baseAssets[1] = address(DAI);
        baseAssets[2] = address(WETH);
        baseAssets[3] = address(WBTC);
        uint256[] memory exchangeRates = priceRouter.getExchangeRates(baseAssets, address(WBTC));
        assertEq(exchangeRates[3], 1e8, "WBTC -> WBTC Exchange Rate Should be 1e8");
    }

    function testAssetRange() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        uint256 min;
        uint256 max;

        //check that exchange rates work when quote == base
        (min, max) = priceRouter.getAssetRange(address(USDC));
        assertEq(min, 1e6, "USDC Min Price Should be 1e7");
        assertEq(max, 1e11, "USDC Max Price Should be 1e11");

        (min, max) = priceRouter.getAssetRange(address(DAI));
        assertEq(min, 1e6, "DAI Min Price Should be 1e4");
        assertEq(max, 1e10, "DAI Max Price Should be 1e8");

        (min, max) = priceRouter.getAssetRange(address(WETH));
        assertEq(min, 1e8, "WETH Min Price Should be 1e4");
        assertEq(max, 1e12, "WETH Max Price Should be 1e8");

        (min, max) = priceRouter.getAssetRange(address(WBTC));
        assertEq(min, 1e9, "WBTC Min Price Should be 1e4");
        assertEq(max, 1e15, "WBTC Max Price Should be 1e8");

        address[] memory baseAssets = new address[](4);
        baseAssets[0] = address(USDC);
        baseAssets[1] = address(DAI);
        baseAssets[2] = address(WETH);
        baseAssets[3] = address(WBTC);

        (uint256[] memory minPrices, uint256[] memory maxPrices) = priceRouter.getAssetsRange(baseAssets);
        assertEq(minPrices[0], 1e6, "USDC Min Price Should be 1e6");
        assertEq(maxPrices[0], 1e11, "USDC Max Price Should be 1e11");
        assertEq(minPrices[1], 1e6, "DAI Min Price Should be 1e6");
        assertEq(maxPrices[1], 1e10, "DAI Max Price Should be 1e10");
        assertEq(minPrices[2], 1e8, "WETH Min Price Should be 1e8");
        assertEq(maxPrices[2], 1e12, "WETH Max Price Should be 1e12");
        assertEq(minPrices[3], 1e9, "WBTC Min Price Should be 1e9");
        assertEq(maxPrices[3], 1e15, "WBTC Max Price Should be 1e15");
    }

    function testGetValue(
        uint256 assets0,
        uint256 assets1,
        uint256 assets2
    ) external {
        assets0 = bound(assets0, 1e6, type(uint72).max);
        assets1 = bound(assets1, 1e18, type(uint112).max);
        assets2 = bound(assets2, 1e8, type(uint48).max);

        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        address[] memory baseAssets = new address[](3);
        baseAssets[0] = address(USDC);
        baseAssets[1] = address(BOND);
        baseAssets[2] = address(WBTC);
        address quoteAsset = address(USDC);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = assets0;
        amounts[1] = assets1;
        amounts[2] = assets2;
        uint256 totalValue = priceRouter.getValue(baseAssets, amounts, quoteAsset);

        //find the value using uniswap

        uint256 sum = assets0; //since the first one is USDC, no conversion is needed

        address[] memory path = new address[](2);
        path[0] = address(BOND);
        path[1] = address(USDC);
        uint256[] memory amountsOut = uniV2Router.getAmountsOut(1e18, path);
        sum += (amountsOut[1] * assets1) / 1e18;

        path[0] = address(WBTC);
        path[1] = address(USDC);
        amountsOut = uniV2Router.getAmountsOut(1e4, path);
        sum += (amountsOut[1] * assets2) / 1e4;

        ///@dev most tests use 1% rel, but WBTC value derived from UniSwap is signifigantly off from historical values,
        /// while the value calculated by the price router is much more accurate
        assertApproxEqRel(
            totalValue,
            sum,
            0.05e18,
            "Total Value of USDC, BOND, and WBTC outside of 10% envelope with UniV2"
        );
    }
}
