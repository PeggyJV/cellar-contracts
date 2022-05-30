// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "../base/ERC4626.sol";

interface ICellarRouter {
    // ======================================= ROUTER OPERATIONS =======================================

    function depositIntoCellarWithPermit(
        ERC4626 cellar,
        uint256 assets,
        address receiver,
        address owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares);

    function depositAndSwapIntoCellar(
        ERC4626 cellar,
        address[] calldata path,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function depositAndSwapIntoCellarWithPermit(
        ERC4626 cellar,
        address[] calldata path,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        address owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares);
}
