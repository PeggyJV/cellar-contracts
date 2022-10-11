// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { Registry } from "src/Registry.sol";
import { Cellar } from "src/base/Cellar.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CellarRouter } from "src/CellarRouter.sol";

contract CellarMultiAssetManagerScript is Script {
    address private uniswapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private strategist = 0x13FBB7e817e5347ce4ae39c3dff1E6705746DCdC;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;
    Registry private registry;

    function run() external {
        vm.startBroadcast();
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniswapV2Router), IUniswapV3Router(uniswapV3Router));
        registry = new Registry(gravityBridge, address(swapRouter), address(priceRouter));

        priceRouter.addAsset(WETH, 0, 0, false, 0);
        priceRouter.addAsset(WBTC, 0, 0, false, 0);
        priceRouter.addAsset(USDC, 0, 0, false, 0);

        createMultiAssetCellars();

        registry.transferOwnership(sommMultiSig);
        priceRouter.transferOwnership(sommMultiSig);

        vm.stopBroadcast();
    }

    function createMultiAssetCellars() internal {
        // Setup Cellar:
        address[] memory positions = new address[](3);
        positions[0] = address(USDC);
        positions[1] = address(WETH);
        positions[2] = address(WBTC);

        Cellar.PositionType[] memory positionTypes = new Cellar.PositionType[](3);
        positionTypes[0] = Cellar.PositionType.ERC20;
        positionTypes[1] = Cellar.PositionType.ERC20;
        positionTypes[2] = Cellar.PositionType.ERC20;

        new Cellar(
            registry,
            USDC,
            positions,
            positionTypes,
            address(USDC),
            Cellar.WithdrawType.PROPORTIONAL,
            "ETH-BTC Trend",
            "ETHBTCTrend",
            strategist
        );

        new Cellar(
            registry,
            USDC,
            positions,
            positionTypes,
            address(USDC),
            Cellar.WithdrawType.PROPORTIONAL,
            "ETH-BTC Momentum",
            "ETHBTCMom",
            strategist
        );
    }
}
