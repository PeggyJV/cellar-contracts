// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IMorpho {
    function userBorrows(address user) external view returns (address[] memory);

    function collateralBalance(address underlying, address user) external view returns (uint256);

    function supplyBalance(address underlying, address user) external view returns (uint256);

    function borrowBalance(address underlying, address user) external view returns (uint256);

    function borrow(
        address underlying,
        uint256 amount,
        address onBehalf,
        address receiver,
        uint256 maxIterations
    ) external returns (uint256);

    function repay(address underlying, uint256 amount, address onBehalf) external returns (uint256);

    function supply(
        address underlying,
        uint256 amount,
        address onBehalf,
        uint256 maxIterations
    ) external returns (uint256);

    function supplyCollateral(address underlying, uint256 amount, address onBehalf) external returns (uint256);

    function withdraw(
        address underlying,
        uint256 amount,
        address onBehalf,
        address receiver,
        uint256 maxIterations
    ) external returns (uint256);

    function withdrawCollateral(
        address underlying,
        uint256 amount,
        address onBehalf,
        address receiver
    ) external returns (uint256);
}
