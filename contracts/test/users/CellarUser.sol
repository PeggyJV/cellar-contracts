// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { AaveV2StablecoinCellar } from "contracts/AaveV2StablecoinCellar.sol";

import { TokenUser } from "./TokenUser.sol";

contract CellarUser is TokenUser {
    AaveV2StablecoinCellar public cellar;

    constructor(AaveV2StablecoinCellar _cellar, ERC20 _token) TokenUser(_token) {
        cellar = _cellar;
    }

    function deposit(uint256 amount, address to) public virtual returns (uint256 shares) {
        return cellar.deposit(amount, to);
    }

    function mint(uint256 shares, address to) public virtual returns (uint256 underlyingAmount) {
        return cellar.mint(shares, to);
    }

    function withdraw(
        uint256 amount,
        address to,
        address from
    ) public virtual returns (uint256 shares) {
        return cellar.withdraw(amount, to, from);
    }

    function redeem(
        uint256 shares,
        address to,
        address from
    ) public virtual returns (uint256 underlyingAmount) {
        return cellar.redeem(shares, to, from);
    }
}
