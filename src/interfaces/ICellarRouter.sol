// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";

interface ICellarRouter {
    // ======================================= ROUTER OPERATIONS =======================================

    function depositIntoCellarWithPermit(
        Cellar cellar,
        uint256 assets,
        address receiver,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares);

    function depositAndSwapIntoCellar(
        Cellar cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver
    ) external returns (uint256 shares);

    function depositAndSwapIntoCellarWithPermit(
        Cellar cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares);

    function withdrawAndSwapFromCellar(
        Cellar cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver
    ) external returns (uint256 shares);

    function withdrawAndSwapFromCellarWithPermit(
        Cellar cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares);
}
