// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFToken {
    // Frax Pair V1 interface.
    // Example Pair: https://etherscan.io/address/0xDbe88DBAc39263c47629ebbA02b3eF4cf0752A72#code
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
    // Example Pair: https://etherscan.io/address/0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15#code
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

    function addCollateral(uint256 _collateralAmount, address _borrower) external;

    function collateralContract() external view returns (address);

    function removeCollateral(uint256 _collateralAmount, address _receiver) external;

    function updateExchangeRate()
        external
        returns (bool _isBorrowAllowed, uint256 _lowExchangeRate, uint256 _highExchangeRate);

    function toBorrowAmount(
        uint256 _shares,
        bool _roundUp,
        bool _previewInterest
    ) external view returns (uint256 _amount);

    function toBorrowAmount(uint256 _shares, bool _roundUp) external view returns (uint256 _amount);

    function toBorrowShares(
        uint256 _amount,
        bool _roundUp,
        bool _previewInterest
    ) external view returns (uint256 _shares);

    function toBorrowShares(uint256 _amount, bool _roundUp) external view returns (uint256);

    function userBorrowShares(address) external view returns (uint256);

    function userCollateralBalance(address) external view returns (uint256);

    function getConstants()
        external
        view
        returns (
            uint256 _LTV_PRECISION,
            uint256 _LIQ_PRECISION,
            uint256 _UTIL_PREC,
            uint256 _FEE_PRECISION,
            uint256 _EXCHANGE_PRECISION,
            uint256 _DEVIATION_PRECISION,
            uint256 _RATE_PRECISION,
            uint256 _MAX_PROTOCOL_FEE
        );

    function asset() external view returns (address);

    function callAddInterest(IFToken fraxlendPair) external;

    function convertToShares(uint256 _assets) external view returns (uint256 _shares);

    function maxLTV() external view returns (uint256 maxLTV);

    struct ExchangeRateInfo {
        address oracle;
        uint32 maxOracleDeviation; // % of larger number, 1e5 precision
        uint184 lastTimestamp;
        uint256 lowExchangeRate;
        uint256 highExchangeRate;
    }

    function exchangeRateInfo() external view returns (ExchangeRateInfo memory exchangeRateInfo);
}
