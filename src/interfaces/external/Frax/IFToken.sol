// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IFToken {
    // Frax Pair V1 interface.
    function deposit(uint256 amount, address receiver) external;

    function redeem(uint256 shares, address receiver, address owner) external;

    function toAssetAmount(uint256 shares, bool roundUp) external view returns (uint256);

    function toAssetShares(uint256 amount, bool roundUp) external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function addInterest()
        external
        returns (uint256 _interestEarned, uint256 _feesAmount, uint256 _feesShare, uint64 _newRate);

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

    function borrowAsset(uint256 borrowAmount, uint256 collateralAmount, address receiver) external;

    function repayAsset(uint256 shares, address borrower) external;

    // Changes for Frax Pair V2 interface.
    struct CurrentRateInfo {
        uint32 lastBlock;
        uint32 feeToProtocolRate; // Fee amount 1e5 precision
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint64 fullUtilizationRate;
    }

    struct VaultAccount {
        uint128 amount; // Total amount, analogous to market cap
        uint128 shares; // Total shares, analogous to shares outstanding
    }

    function toAssetAmount(uint256 shares, bool roundUp, bool previewInterest) external view returns (uint256);

    function toAssetShares(uint256 amount, bool roundUp, bool previewInterest) external view returns (uint256);

    function withdraw(uint256 assets, address receiver, address owner) external;

    function addInterest(
        bool returnAccounting
    )
        external
        returns (
            uint256 _interestEarned,
            uint256 _feesAmount,
            uint256 _feesShare,
            CurrentRateInfo memory _currentRateInfo,
            VaultAccount memory _totalAsset,
            VaultAccount memory _totalBorrow
        );
}
