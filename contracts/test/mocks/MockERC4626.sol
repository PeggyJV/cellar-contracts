// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { ERC4626 } from "../../interfaces/ERC4626.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { MockERC20 } from "./MockERC20.sol";

contract MockERC4626 is ERC4626 {
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC4626(_asset, _name, _symbol, _decimals) {}

    function freeDeposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        MockERC20(address(asset)).mint(address(this), assets);

        _mint(receiver, shares);
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
