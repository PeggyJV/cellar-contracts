// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { ERC20, SafeTransferLib } from "src/base/Cellar.sol";

contract TEnv {
    // General Variables.
    address public strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address public devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address public gravityBridge = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    CellarFactory public factory = CellarFactory(0xFCed747657ACfFc6FAfacD606E17D0988EDf3Fd9);
    Registry public registry = Registry(0xd1c18363F81d8E6260511b38FcF1e8b710E7e31D);
    PriceRouter public priceRouter = PriceRouter(0xD8029A05bEB0FaF1215fBb064D98c39B28d317Ee);
    SwapRouter public swapRouter = SwapRouter(0xC356F0AC3a0d3fC18167d8ee62e0A8FB487D1719);

    // Common ERC20s.
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // Chainlink PriceFeeds
    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    address public USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address public WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // Registry Positions.
    // Euler positions.
    uint32 public eUsdcPosition = 1;
    uint32 public eDaiPosition = 2;
    uint32 public eUsdtPosition = 3;
    uint32 public eUsdcLiquidPosition = 4;
    uint32 public eDaiLiquidPosition = 5;
    uint32 public eUsdtLiquidPosition = 6;
    uint32 public debtUsdcPosition = 10;
    uint32 public debtDaiPosition = 11;
    uint32 public debtUsdtPosition = 12;
}
