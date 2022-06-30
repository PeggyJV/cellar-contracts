// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Registry is Ownable {
    address public swapRouter;
    address public gravityBridge;
    address public priceRouter;

    /**
     * @notice Emitted when the swap router is changed.
     * @param oldSwapRouter address of SwapRouter contract was changed from
     * @param newSwapRouter address of SwapRouter contract was changed to
     */
    event SwapRouterChanged(
        address oldSwapRouter,
        address newSwapRouter
    );

    /**
     * @notice Emitted when the Gravity Bridge is changed.
     * @param oldGravityBridge address of GravityBridge contract was changed from
     * @param newGravityBridge address of GravityBridge contract was changed to
     */
    event GravityBridgeChanged(
        address oldGravityBridge,
        address newGravityBridge
    );

    /**
     * @notice Emitted when the price router is changed.
     * @param oldPriceRouter address of PriceRouter contract was changed from
     * @param newPriceRouter address of PriceRouter contract was changed to
     */
    event PriceRouterChanged(
        address oldPriceRouter,
        address newPriceRouter
    );

    /**
     * @notice Sets new address of SwapRouter contract.
     * @param newSwapRouter new SwapRouter address
     */
    function setSwapRouter(address newSwapRouter) external onlyOwner {
        address oldSwapRouter = swapRouter;
        swapRouter = newSwapRouter;
        
        emit SwapRouterChanged(oldSwapRouter, newSwapRouter);
    }

    /**
     * @notice Sets new address of GravityBridge contract.
     * @param newGravityBridge new GravityBridge address
     */
    function setGravityBridge(address newGravityBridge) external onlyOwner {
        address oldGravityBridge = gravityBridge;
        gravityBridge = newGravityBridge;

        emit GravityBridgeChanged(oldGravityBridge, newGravityBridge);
    }

    /**
     * @notice Sets new address of PriceRouter contract.
     * @param newPriceRouter new PriceRouter address
     */
    function setPriceRouter(address newPriceRouter) external onlyOwner {
        address oldPriceRouter = priceRouter;
        priceRouter = newPriceRouter;

        emit PriceRouterChanged(oldPriceRouter, newPriceRouter);
    }

    /**
     * @notice Configures default addresses of contracts
     * @param _swapRouter address of SwapRouter contract
     * @param _gravityBridge address of GravityBridge contract
     * @param _priceRouter address of PriceRouter contract
     */
    constructor(
        address _swapRouter,
        address _gravityBridge,
        address _priceRouter
    ) Ownable() {
        swapRouter = _swapRouter;
        gravityBridge = _gravityBridge;
        priceRouter = _priceRouter;
    }
}
