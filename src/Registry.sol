// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IGravity } from "./interfaces/IGravity.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Registry is Ownable {
    SwapRouter public swapRouter;
    PriceRouter public priceRouter;
    IGravity public gravityBridge;

    /**
     * @notice Emitted when the swap router is changed.
     * @param oldSwapRouter address of SwapRouter contract was changed from
     * @param newSwapRouter address of SwapRouter contract was changed to
     */
    event SwapRouterChanged(address oldSwapRouter, address newSwapRouter);

    /**
     * @notice Emitted when the Gravity Bridge is changed.
     * @param oldGravityBridge address of GravityBridge contract was changed from
     * @param newGravityBridge address of GravityBridge contract was changed to
     */
    event GravityBridgeChanged(address oldGravityBridge, address newGravityBridge);

    /**
     * @notice Emitted when the price router is changed.
     * @param oldPriceRouter address of PriceRouter contract was changed from
     * @param newPriceRouter address of PriceRouter contract was changed to
     */
    event PriceRouterChanged(address oldPriceRouter, address newPriceRouter);

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
        address oldSwapRouter = address(swapRouter);
        swapRouter = newSwapRouter;

        emit SwapRouterChanged(oldSwapRouter, address(newSwapRouter));
    }

    function setPriceRouter(PriceRouter newPriceRouter) external onlyOwner {
        address oldPriceRouter = address(priceRouter);
        priceRouter = newPriceRouter;

        emit PriceRouterChanged(oldPriceRouter, address(newPriceRouter));
    }

    function setGravityBridge(IGravity newGravityBridge) external onlyOwner {
        address oldGravityBridge = address(newGravityBridge);
        gravityBridge = newGravityBridge;

        emit GravityBridgeChanged(oldGravityBridge, address(newGravityBridge));
    }
}
