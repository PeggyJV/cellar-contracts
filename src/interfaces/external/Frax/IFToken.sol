// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IFToken {
    function deposit(uint256 amount, address receiver) external;

    function redeem(uint256 shares, address receiver, address owner) external;

    function toAssetAmount(uint256 shares, bool roundUp) external view returns (uint256);

    function toAssetShares(uint256 amount, bool roundUp) external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function getPairAccounting()
        external
        view
        returns (
            uint128 totalAssetAmount,
            uint128 totalAssetShares,
            uint128 totalBorrowAmount,
            uint128 totalBorrowShares,
            uint256 totalCollateral
        );
}
