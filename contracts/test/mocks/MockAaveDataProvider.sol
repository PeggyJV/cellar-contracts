// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

contract MockAaveDataProvider {
    function getUserReserveData(address, address)
        external
        pure
        returns (
            uint256 currentATokenBalance,
            uint256 currentStableDebt,
            uint256 currentVariableDebt,
            uint256 principalStableDebt,
            uint256 scaledVariableDebt,
            uint256 stableBorrowRate,
            uint256 liquidityRate,
            uint40 stableRateLastUpdated,
            bool usageAsCollateralEnabled
        )
    {
        currentATokenBalance = 100500;
        currentVariableDebt = 0;
        currentStableDebt = 0;
        principalStableDebt = 0;
        scaledVariableDebt = 0;
        liquidityRate = 0;
        stableBorrowRate = 0;
        stableRateLastUpdated = 0;
        usageAsCollateralEnabled = false;
    }

    function getReserveData(address)
        external
        pure
        returns (
            uint256 availableLiquidity,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        )
    {
        return (100500500, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }
}
