// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { PriceRouter, Registry, ERC20 } from "src/modules/PriceRouter.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { IGravity } from "src/interfaces/IGravity.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract PriceRouterTest is Test {
    using Math for uint256;

    PriceRouter private priceRouter;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    function setUp() external {
        priceRouter = new PriceRouter();
    }

    function testExchangeRate() external view {
        console.log("WETH/WBTC", priceRouter.getExchangeRate(WETH, WBTC));
        console.log("WBTC/WETH", priceRouter.getExchangeRate(WBTC, WETH));
        console.log("WETH/USDC", priceRouter.getExchangeRate(WETH, USDC));
        console.log("USDC/WETH", priceRouter.getExchangeRate(USDC, WETH));
    }

    function testGetValue() external view {
        console.log("1 WETH in WBTC", priceRouter.getValue(WETH, 1e18, WBTC));
        console.log("1 WBTC in WETH", priceRouter.getValue(WBTC, 1e8, WETH));
        console.log("1 WETH in USDC", priceRouter.getValue(WETH, 1e18, USDC));
        console.log("1 USDC in WETH", priceRouter.getValue(USDC, 1e6, WETH));
    }
}
