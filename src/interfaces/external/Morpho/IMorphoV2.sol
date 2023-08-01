// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IMorphoV2 {
    struct PoolIndexes {
        uint32 lastUpdateTimestamp; // The last time the local pool and peer-to-peer indexes were updated.
        uint112 poolSupplyIndex; // Last pool supply index. Note that for the stEth market, the pool supply index is tweaked to take into account the staking rewards.
        uint112 poolBorrowIndex; // Last pool borrow index. Note that for the stEth market, the pool borrow index is tweaked to take into account the staking rewards.
    }

    function userMarkets(address user) external view returns (bytes32);

    function borrowBalanceInOf(address poolToken, address user) external view returns (uint256 inP2P, uint256 onPool);

    function supplyBalanceInOf(address poolToken, address user) external view returns (uint256 inP2P, uint256 onPool);

    function poolIndexes(address poolToken) external view returns (PoolIndexes memory);

    function p2pSupplyIndex(address poolToken) external view returns (uint256);

    function p2pBorrowIndex(address poolToken) external view returns (uint256);

    function supply(address poolToken, uint256 amount) external;

    function borrow(address poolToken, uint256 amount) external;

    function repay(address poolToken, uint256 amount) external;

    function withdraw(address poolToken, uint256 amount, address receiver) external;
}
