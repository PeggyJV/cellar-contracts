// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SwapRouter } from "./modules/SwapRouter.sol";
import { PriceRouter } from "./modules/PriceRouter.sol";
import { IGravity } from "./interfaces/IGravity.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// TODO: configure defaults
// TODO: add natspec
// TODO: add events

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

    function setSwapRouter(SwapRouter newSwapRouter) external {
        swapRouter = newSwapRouter;
    }

    function setPriceRouter(PriceRouter newPriceRouter) external {
        priceRouter = newPriceRouter;
    }

    function setGravityBridge(IGravity newGravityBridge) external {
        gravityBridge = newGravityBridge;
    }
}
