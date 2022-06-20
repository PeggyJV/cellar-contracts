// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ChainlinkPriceFeedAdaptor } from "src/ChainlinkPriceFeedAdaptor.sol";
import { OracleRouter } from "src/OracleRouter.sol";
import { PriceRouter } from "src/PriceRouter.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract PriceRouterTest is Test {
    using Math for uint256;

    ChainlinkPriceFeedAdaptor private chainlinkAdaptor;
    OracleRouter private oracleRouter;
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
    FeedRegistryInterface private FeedRegistry = FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);

    function setUp() public {
        chainlinkAdaptor = new ChainlinkPriceFeedAdaptor(FeedRegistry);
        oracleRouter = new OracleRouter(address(chainlinkAdaptor)); //make chainlink adaptor the default adaptor
        priceRouter = new PriceRouter(oracleRouter);
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

        exchangeRate = priceRouter.getExchangeRate(address(BOND), address(USDC)); //weird asset with an ETH price but no USD price
        assertApproxEqAbs(exchangeRate, 2.65e6, 1000, "BOND -> USDC Exchange Rate Should be 2.65 USDC");

        //check exchange rates work
        //TODO bring in swap exchange data to check these exchange rates
        exchangeRate = priceRouter.getExchangeRate(address(DAI), address(USDC));
        assertApproxEqAbs(exchangeRate, 1e6, 1000, "DAI -> USDC Exchange Rate Should be 1 +- 0.001 USDC");

        exchangeRate = priceRouter.getExchangeRate(address(WETH), address(WBTC));
        //assertApproxEqAbs(exchangeRate, 1e6, 1000, "WETH -> WBTC Exchange Rate Should be 0.5 +- 0.1 BTC");

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
        assertEq(minPrices[0], 1e6, "USDC Min Price Should be 1e7");
        assertEq(maxPrices[0], 1e11, "USDC Max Price Should be 1e11");
        assertEq(minPrices[1], 1e6, "DAI Min Price Should be 1e4");
        assertEq(maxPrices[1], 1e10, "DAI Max Price Should be 1e8");
        assertEq(minPrices[2], 1e8, "WETH Min Price Should be 1e4");
        assertEq(maxPrices[2], 1e12, "WETH Max Price Should be 1e8");
        assertEq(minPrices[3], 1e9, "WBTC Min Price Should be 1e4");
        assertEq(maxPrices[3], 1e15, "WBTC Max Price Should be 1e8");
    }

    function testGetValue() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        address[] memory baseAssets = new address[](3);
        baseAssets[0] = address(USDC);
        baseAssets[1] = address(USDC);
        baseAssets[2] = address(USDC);
        address quoteAsset = address(USDC);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e6;
        amounts[1] = 100e6;
        amounts[2] = 100e6;
        uint256 totalValue = priceRouter.getValue(baseAssets, amounts, quoteAsset);
        assertEq(totalValue, 300e6, "Total Value should be sum of all amounts");
    }
}
