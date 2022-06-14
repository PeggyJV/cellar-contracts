// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// TODO: configure defaults
// TODO: add natspec
// TODO: add events

contract Registry is Ownable {
    address public swapRouter;
    address public gravityBridge;

    function setSwapRouter(address newSwapRouter) external {
        swapRouter = newSwapRouter;
    }

    function setGravityBridge(address newGravityBridge) external {
        gravityBridge = newGravityBridge;
    }
}
