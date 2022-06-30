// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { MockERC20 } from "./MockERC20.sol";
import { Math } from "src/utils/Math.sol";

contract MockERC20WithTransferFee is MockERC20 {
    using Math for uint256;

    uint256 public constant transferFee = 0.01e18;

    constructor(string memory _symbol, uint8 _decimals) MockERC20(_symbol, _decimals) {}

    function transfer(address to, uint256 amount) public override returns (bool) {
        balanceOf[msg.sender] -= amount;

        amount -= amount.mulWadDown(transferFee);

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        amount -= amount.mulWadDown(transferFee);

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }
}
