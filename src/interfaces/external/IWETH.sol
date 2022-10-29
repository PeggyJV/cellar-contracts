// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}
