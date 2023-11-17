// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IPoolRegistry {
    function poolLength() external view returns(uint256);
    function poolInfo(uint256 _pid) external view returns(address, address, address, uint8);
    function vaultMap(uint256 _pid, address _user) external view returns(address vault);
    function addUserVault(uint256 _pid, address _user) external returns(address vault, address stakeAddress, address stakeToken, address rewards);
    function deactivatePool(uint256 _pid) external;
    function addPool(address _implementation, address _stakingAddress, address _stakingToken) external;
    function setRewardActiveOnCreation(bool _active) external;
    function setRewardImplementation(address _imp) external;
}