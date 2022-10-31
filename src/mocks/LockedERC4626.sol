// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626 } from "src/base/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Math } from "../utils/Math.sol";
import { Test, console } from "@forge-std/Test.sol";

contract LockedERC4626 is ERC4626, Test {
    using Math for uint256;

    uint256 public immutable percentLocked;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _percentLocked
    ) ERC4626(_asset, _name, _symbol, 18) {
        percentLocked = _percentLocked;
    }

    function totalAssets() public view override returns (uint256 assets) {
        return asset.balanceOf(address(this));
    }

    // Set maxWithdraw to zero to simulate funds being lockec in contract.
    function maxWithdraw(address) public view override returns (uint256) {
        return totalAssets().mulWadDown((1e18 - percentLocked));
    }
}
