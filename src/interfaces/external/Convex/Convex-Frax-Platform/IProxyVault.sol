// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IProxyVault {
    enum VaultType {
        Erc20Basic,
        UniV3,
        Convex,
        Erc20Joint
    }

    function initialize(
        address _owner,
        address _stakingAddress,
        address _stakingToken,
        address _rewardsAddress
    ) external;

    function usingProxy() external returns (address);

    function owner() external returns (address);

    function stakingAddress() external returns (address);

    function rewards() external returns (address);

    function getReward() external;

    function getReward(bool _claim) external;

    function getReward(bool _claim, address[] calldata _rewardTokenList) external;

    function earned() external returns (address[] memory token_addresses, uint256[] memory total_earned);

    /// Extra Functions for Integrating Sommelier Cellars w/ Convex-Frax Platform contracts on Mainnet

    function stakeLockedCurveLp(uint256 _liquidity, uint256 _secs) external;

    function withdrawLockedAndUnwrap(bytes32 _kek_id) external;

    function lockAdditionalCurveLp(bytes32 _kek_id, uint256 _addl_liq) external;

    function lockLonger(bytes32 _kek_id, uint256 new_ending_ts) external;

    function getReward() external;
}
