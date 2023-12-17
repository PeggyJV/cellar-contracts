// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface ComptrollerG7 {
    function claimComp(address user) external;

    function markets(address market) external view returns (bool, uint256, bool);

    function compAccrued(address user) external view returns (uint256);

    // Functions from ComptrollerInterface.sol to supply collateral that enable open borrows
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);

    function exitMarket(address cToken) external returns (uint);

    function getAssetsIn(address account) external view returns (CErc20[] memory);

    function oracle() external view returns (PriceOracle oracle);
}

interface CErc20 {
    function underlying() external view returns (address);

    function balanceOf(address user) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function borrowBalanceCurrent(address account) external view returns (uint);

    function mint(uint256 mintAmount) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function borrow(uint borrowAmount) external returns (uint);

    function repayBorrow(uint repayAmount) external returns (uint);

    function accrueInterest() external returns (uint);

    function borrowBalanceStored(address account) external view returns (uint);

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by comptroller to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (possible error, token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
}

interface PriceOracle {
    /**
     * @notice Get the underlying price of a cToken asset
     * @param cToken The cToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18).
     *  Zero means the price is unavailable.
     *  TODO: param is originally CToken, in general since we are going to work with native ETH too we may want to bring in CToken vs bringing in just CErc20
     */
    function getUnderlyingPrice(CErc20 cToken) external view returns (uint);
}

interface CEther {
    function underlying() external view returns (address);

    function balanceOf(address user) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function borrowBalanceCurrent(address account) external view returns (uint);

    function mint() external payable;

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function borrow(uint borrowAmount) external returns (uint);

    function repayBorrowBehalf(address borrower) external payable;

    function accrueInterest() external returns (uint);

    function borrowBalanceStored(address account) external view returns (uint);

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by comptroller to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (possible error, token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
}
