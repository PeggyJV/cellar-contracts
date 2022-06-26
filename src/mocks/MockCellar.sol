// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { Cellar, Registry, ERC4626, ERC20 } from "src/base/Cellar.sol";
import { Test, console } from "@forge-std/Test.sol";

contract MockCellar is Cellar, Test {
    constructor(
        Registry _registry,
        ERC20 _asset,
        address[] memory _positions,
        string memory _name,
        string memory _symbol
    ) Cellar(_registry, _asset, _positions, _name, _symbol) {}

    function increasePositionBalance(address position, uint256 amount) external {
        deal(address(ERC4626(position).asset()), address(this), amount);

        // Update position balance.
        getPositionData[position].balance += amount;

        // Deposit into position.
        ERC4626(position).deposit(amount, address(this));
    }
}
