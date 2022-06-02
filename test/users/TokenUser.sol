// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract TokenUser {
    ERC20 public token;

    constructor(ERC20 _token) {
        token = _token;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        return token.approve(spender, amount);
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        return token.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}
