// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ERC20 } from "src/base/Cellar.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract UseTimelockVestingContract is Test {
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private sevenSeas = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    ERC20 private somm = ERC20(0xa670d7237398238DE01267472C6f13e5B8010FD1);

    TimelockController private timelock = TimelockController(payable(0xAa71f75fb6948a6c814A28675241FC5E3bCaC355));

    function setUp() external {}

    function testTimelock() external {
        // Send 200_000 somm to timelock.
        uint256 assets = 200_000e6;
        deal(address(somm), address(timelock), assets);

        // Crispy proposes transfer.
        bytes memory data = abi.encodeWithSelector(ERC20.transfer.selector, sevenSeas, assets);
        vm.prank(devOwner);
        timelock.schedule(address(somm), 0, data, hex"", hex"", 2 * 365 days);

        // 2 years pass.
        vm.warp(block.timestamp + (2 * 365 days));

        uint256 sommBalance = somm.balanceOf(sevenSeas);
        // 7seas multisig claims their tokens.
        vm.prank(sevenSeas);
        timelock.execute(address(somm), 0, data, hex"", hex"");

        sommBalance = somm.balanceOf(sevenSeas) - sommBalance;

        assertEq(sommBalance, assets, "7seas wallet should have assets amount of somm.");
    }
}
