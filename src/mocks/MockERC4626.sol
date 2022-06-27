// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626 } from "src/base/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { MockERC20 } from "./MockERC20.sol";

import { Test } from "@forge-std/Test.sol";

contract MockERC4626 is ERC4626, Test {
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC4626(_asset, _name, _symbol, _decimals) {}

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    function burn(address from, uint256 value) external {
        _burn(from, value);
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
