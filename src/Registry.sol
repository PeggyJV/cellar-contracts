// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// TODO: configure defaults
// TODO: add events

contract Registry is Ownable {
    address public swapRouter;
    address public gravityBridge;
    address public priceRouter;

    /**
     * @notice Sets new address of SwapRouter contract.
     * @param newSwapRouter new SwapRouter address
     */
    function setSwapRouter(address newSwapRouter) external onlyOwner {
        swapRouter = newSwapRouter;
    }

    /**
     * @notice Sets new address of GravityBridge contract.
     * @param newGravityBridge new GravityBridge address
     */
    function setGravityBridge(address newGravityBridge) external onlyOwner {
        gravityBridge = newGravityBridge;
    }

    /**
     * @notice Sets new address of PriceRouter contract.
     * @param newPriceRouter new PriceRouter address
     */
    function setPriceRouter(address newPriceRouter) external onlyOwner {
        priceRouter = newPriceRouter;
    }
}
