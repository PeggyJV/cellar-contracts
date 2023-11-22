// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IBooster {
    function addPool(address _implementation, address _stakingAddress, address _stakingToken) external;

    function deactivatePool(uint256 _pid) external;

    function voteGaugeWeight(address _controller, address _gauge, uint256 _weight) external;

    function setDelegate(address _delegateContract, address _delegate, bytes32 _space) external;

    function owner() external returns (address);

    function rewardManager() external returns (address);

    function isShutdown() external returns (bool);

    /// extra functions to access Convex-Frax Booster
    function createVault(uint256 _pid) external returns (address);
}
