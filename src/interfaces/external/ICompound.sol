// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface ComptrollerG7 {
    function claimComp(address user) external;

    function markets(address market) external view returns (bool, uint256, bool);

    function compAccrued(address user) external view returns (uint256);
}

interface CErc20 {
    function underlying() external view returns (address);

    function balanceOf(address user) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function mint(uint256 mintAmount) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);
}
