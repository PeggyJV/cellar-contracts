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
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract CellarMultiAssetManagerScript is Script {
    address private uniswapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private mockGravityBridge = 0xF07Ba2229b4Da47895ce0a4Ab4298ad7F8Cb3a4D; // Address you want as the owner
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    PriceRouter priceRouter;
    SwapRouter swapRouter;
    Registry registry;

    function run() external {
        vm.startBroadcast();
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniswapV2Router), IUniswapV3Router(uniswapV3Router));
        registry = new Registry(mockGravityBridge, address(swapRouter), address(priceRouter));

        priceRouter.addAsset(WETH, 0, 0, false, 0);
        priceRouter.addAsset(WBTC, 0, 0, false, 0);
        priceRouter.addAsset(USDC, 0, 0, false, 0);

        createMultiAssetCellar();

        // Set registry to use correct gravity bridge.
        registry.setAddress(0, gravityBridge);

        vm.stopBroadcast();
    }

    function createMultiAssetCellar() internal {
        // Setup Cellar:
        address[] memory positions = new address[](3);
        positions[0] = address(USDC);
        positions[1] = address(WETH);
        positions[2] = address(WBTC);

        Cellar.PositionData[] memory positionData = new Cellar.PositionData[](3);
        positionData[0] = Cellar.PositionData({
            positionType: Cellar.PositionType.ERC20,
            adaptor: address(0),
            adaptorData: abi.encode(0)
        });
        positionData[1] = Cellar.PositionData({
            positionType: Cellar.PositionType.ERC20,
            adaptor: address(0),
            adaptorData: abi.encode(0)
        });
        positionData[2] = Cellar.PositionData({
            positionType: Cellar.PositionType.ERC20,
            adaptor: address(0),
            adaptorData: abi.encode(0)
        });

        new Cellar(
            registry,
            USDC,
            positions,
            positionData,
            address(USDC),
            Cellar.WithdrawType.ORDERLY,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            mockGravityBridge
        );
    }
}
