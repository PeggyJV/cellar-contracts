// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IGravity } from "./interfaces/IGravity.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// TODO: configure defaults
// TODO: add natspec
// TODO: add events
//TODO should this be deployed first with no constructor args?

contract Registry is Ownable {
    SwapRouter public swapRouter;
    PriceRouter public priceRouter;
    IGravity public gravityBridge;

    constructor(
        SwapRouter _swapRouter,
        PriceRouter _priceRouter,
        IGravity _gravityBridge
    ) {
        swapRouter = _swapRouter;
        priceRouter = _priceRouter;
        gravityBridge = _gravityBridge;
    }

    function setSwapRouter(SwapRouter newSwapRouter) external onlyOwner {
        swapRouter = newSwapRouter;
    }

    function setPriceRouter(PriceRouter newPriceRouter) external onlyOwner {
        priceRouter = newPriceRouter;
    }

    function setGravityBridge(IGravity newGravityBridge) external onlyOwner {
        gravityBridge = newGravityBridge;
    }
}
