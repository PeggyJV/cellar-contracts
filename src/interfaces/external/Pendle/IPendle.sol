// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IMarketFactory {
    function isValidMarket(address) external view returns (bool);
}

interface IPendleMarket {
    function readTokens() external view returns (address SY, address PT, address YT);
}

interface ISyToken {
    function getTokensIn() external view returns (address[] memory);
    function exchangeRate() external view returns (uint256);
}

interface IYT {
    function isExpired() external view returns (bool);
}
