// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";

contract DeploySwapRouterWithApprovalFixScript is Script {
    address private uniswapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    SwapRouter private swapRouter;

    function run() external {
        vm.startBroadcast();
        swapRouter = new SwapRouter(IUniswapV2Router(uniswapV2Router), IUniswapV3Router(uniswapV3Router));
        vm.stopBroadcast();
    }
}
