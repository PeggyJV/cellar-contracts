// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ERC4626 } from "src/base/ERC4626.sol";

interface ICellarRouter {
    // ======================================= ROUTER OPERATIONS =======================================

    function depositIntoCellarWithPermit(
        ERC4626 cellar,
        uint256 assets,
        address receiver,
        uint256 deadline,
        uint256 minSharesIn,
        bytes memory signature
    ) external returns (uint256 shares);

    function depositAndSwapIntoCellar(
        ERC4626 cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        uint256 minSharesIn
    ) external returns (uint256 shares);

    function depositAndSwapIntoCellarWithPermit(
        ERC4626 cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        uint256 deadline,
        uint256 minSharesIn,
        bytes memory signature
    ) external returns (uint256 shares);

    function withdrawAndSwapFromCellar(
        ERC4626 cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        uint256 minSharesIn
    ) external returns (uint256 shares);

    function withdrawAndSwapFromCellarWithPermit(
        ERC4626 cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        uint256 deadline,
        uint256 minSharesIn,
        bytes memory signature
    ) external returns (uint256 shares);
}
