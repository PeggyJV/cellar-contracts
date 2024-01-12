// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface IComet {
    struct AssetInfo {
        uint8 offset;
        address asset;
        address priceFeed;
        uint64 scale;
        uint64 borrowCollateralFactor;
        uint64 liquidateCollateralFactor;
        uint64 liquidationFactor;
        uint128 supplyCap;
    }

    function getAssetInfo(uint8 i) external view returns (AssetInfo memory);

    function baseToken() external view returns (ERC20);

    function supply(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;

    function withdrawTo(address to, address asset, uint256 amount) external;

    function balanceOf(address user) external view returns (uint256);

    function userCollateral(address user, address asset) external view returns (uint128 collateral, uint128 reserves);

    function borrowBalanceOf(address user) external view returns (uint256 borrowedBase);

    function numAssets() external view returns (uint8);

    function getPrice(address) external view returns (uint128);

    function baseTokenPriceFeed() external view returns (address);
}
