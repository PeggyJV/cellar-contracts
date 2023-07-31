// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IMorphoV3 {
    struct LiquidityData {
        uint256 borrowable; // The maximum debt value allowed to borrow (in base currency).
        uint256 maxDebt; // The maximum debt value allowed before being liquidatable (in base currency).
        uint256 debt; // The debt value (in base currency).
    }

    function liquidityData(address user) external view returns (LiquidityData memory);

    function userBorrows(address user) external view returns (address[] memory);

    function collateralBalance(address underlying, address user) external view returns (uint256);

    function supplyBalance(address underlying, address user) external view returns (uint256);

    function borrowBalance(address underlying, address user) external view returns (uint256);

    function scaledP2PBorrowBalance(address underlying, address user) external view returns (uint256);

    function scaledP2PSupplyBalance(address underlying, address user) external view returns (uint256);

    function scaledPoolBorrowBalance(address underlying, address user) external view returns (uint256);

    function scaledPoolSupplyBalance(address underlying, address user) external view returns (uint256);

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
