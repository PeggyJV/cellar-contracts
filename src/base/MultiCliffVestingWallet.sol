// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { SafeTransferLib } from "src/base/SafeTransferLib.sol";

contract MultiCliffVestingWallet {
    using SafeTransferLib for ERC20;

    event VestCreated(address _beneficiary, uint256 _duration, address _token, uint256 _amount, uint256 _start);

    event VestClaimed(address _beneficiary, uint256 _duration, address _token, uint256 _amount, uint256 _start);

    mapping(bytes32 => bool) public vestIsValid;

    function createVest(address _beneficiary, uint256 _duration, address _token, uint256 _amount) external {
        uint256 start = block.timestamp;
        bytes32 vestingHash = keccak256(abi.encode(_beneficiary, _duration, _token, _amount, start));

        if (_beneficiary == address(0)) revert("Zero Beneficiary");

        if (vestIsValid[vestingHash]) revert("Hash collision");

        ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        vestIsValid[vestingHash] = true;

        emit VestCreated(_beneficiary, _duration, _token, _amount, start);
    }

    function claimVest(
        address _beneficiary,
        uint256 _duration,
        address _token,
        uint256 _amount,
        uint256 _start
    ) external {
        if (block.timestamp < (_duration + _start)) revert("Vest still pending");

        bytes32 vestingHash = keccak256(abi.encode(_beneficiary, _duration, _token, _amount, _start));

        // Make sure vest is actually valid.
        if (!vestIsValid[vestingHash]) revert("Vest not valid");

        // Set vestIsValid to false.
        vestIsValid[vestingHash] = false;

        // Payout vested tokens to beneficiary.
        ERC20(_token).safeTransfer(_beneficiary, _amount);

        emit VestClaimed(_beneficiary, _duration, _token, _amount, _start);
    }
}
