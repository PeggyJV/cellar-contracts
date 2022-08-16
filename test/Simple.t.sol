// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Registry } from "src/Registry.sol";
import { Cellar } from "src/base/Cellar.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RegistryTest is Test {
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    Cellar private cellar;

    function setUp() external {
        cellar = Cellar(0xDde063eBe8E85D666AD99f731B4Dbf8C98F29708);
    }

    function testDeposit() external {
        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(cellar), 100e6);
        cellar.deposit(100e6, address(this));
        console.log("Cellar USDC Balance", USDC.balanceOf(address(cellar)));
    }
}
