// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ICellar } from "../interfaces/ICellar.sol";

interface ICellarRouter {
    // ======================================= ROUTER OPERATIONS =======================================

    function depositIntoCellarWithPermit(
        ICellar cellar,
        uint256 assets,
        address receiver,
        address owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares);

    function depositAndSwapIntoCellar(
        ICellar cellar,
        address[] calldata path,
        uint256 assets,
        uint256 minAssetsOut,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function depositAndSwapIntoCellarWithPermit(
        ICellar cellar,
        address[] calldata path,
        uint256 assets,
        uint256 minAssetsOut,
        address receiver,
        address owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares);
}
