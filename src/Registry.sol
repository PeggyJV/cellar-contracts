// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// TODO: configure defaults
// TODO: add natspec
// TODO: add events

contract Registry is Ownable {
    address public swapRouter;
    address public gravityBridge;
    address public priceRouter;

    function setSwapRouter(address newSwapRouter) external onlyOwner {
        swapRouter = newSwapRouter;
    }

    function setGravityBridge(address newGravityBridge) external onlyOwner {
        gravityBridge = newGravityBridge;
    }

    function setPriceRouter(address newPriceRouter) external onlyOwner {
        priceRouter = newPriceRouter;
    }
}
