// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";

interface ICellarRouter {
    // ======================================= ROUTER OPERATIONS =======================================

    function depositWithPermit(
        Cellar cellar,
        uint256 assets,
        address receiver,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares);

    function depositAndSwap(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        address receiver,
        ERC20 assetIn
    ) external returns (uint256 shares);

    function depositAndSwapWithPermit(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        ERC20 assetIn,
        address reciever,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares);

    function withdrawAndSwap(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    function withdrawAndSwapWithPermit(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        uint256 deadline,
        bytes memory signature,
        address receiver
    ) external returns (uint256 shares);
}
