// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";

interface ICellarRouter {
    // ======================================= ROUTER OPERATIONS =======================================

    function depositWithPermit(
        Cellar cellar,
        uint256 assets,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares);

    function depositAndSwap(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        ERC20 assetIn
    ) external returns (uint256 shares);

    function depositAndSwapWithPermit(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        ERC20 assetIn,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares);

    function withdrawAndSwap(
        Cellar cellar,
        SwapRouter.Exchange[] calldata exchanges,
        bytes[] calldata swapDatas,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    function withdrawAndSwapWithPermit(
        Cellar cellar,
        SwapRouter.Exchange[] calldata exchanges,
        bytes[] calldata swapDatas,
        uint256 sharesToRedeem,
        uint256 deadline,
        bytes memory signature,
        address receiver
    ) external returns (uint256 shares);
}
