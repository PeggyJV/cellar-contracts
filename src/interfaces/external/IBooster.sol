// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// Convex IBooster interface
interface IBooster {
    function owner() external view returns(address);
    function poolLength() external view returns (uint256);
    function poolInfo(uint256 _pid) external view returns(address, address, address, address, address, bool);

    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
    function depositAll(uint256 _pid, bool _stake) external returns(bool);
    function withdraw(uint256 _pid, uint256 _amount) external returns(bool);
    function withdrawTo(uint256 _pid, uint256 _amount, address _to) external returns(bool);
    function withdrawAll(uint256 _pid) external returns(bool);
    function claimRewards(uint256 _pid, address _gauge) external returns(bool);
    function vote(uint256 _voteId, address _votingAddress, bool _support) external returns(bool);
    function voteGaugeWeight(address[] calldata _gauge, uint256[] calldata _weight ) external returns(bool);
    function setVoteDelegate(address _voteDelegate) external;
}