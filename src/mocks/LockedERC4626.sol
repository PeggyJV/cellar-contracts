// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, ERC20, SafeTransferLib } from "src/base/ERC4626.sol";
import { Test, console } from "@forge-std/Test.sol";

contract LockedERC4626 is ERC4626, Test {
    using SafeTransferLib for ERC20;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC4626(_asset, _name, _symbol, _decimals) {}

    function totalAssets() public view override returns (uint256 assets) {
        return asset.balanceOf(address(this));
    }

    // Set maxWithdraw to zero to simulate funds being lockec in contract.
    function maxWithdraw(address owner) public view override returns (uint256) {
        return 0;
    }
}
