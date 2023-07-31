// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC20, ERC4626, SafeTransferLib, ERC20 } from "src/base/Cellar.sol";
import { Test, stdStorage, StdStorage, stdError } from "@forge-std/Test.sol";

contract ReentrancyERC4626 is ERC4626, Test {
    using SafeTransferLib for ERC20;
    using stdStorage for StdStorage;

    // True tries reentrancy, False manipulates callers totalSupply
    bool private immutable style;

    constructor(ERC20 _asset, string memory _name, string memory _symbol, bool _style) ERC4626(_asset, _name, _symbol) {
        style = _style;
    }

    function totalAssets() public view override returns (uint256 assets) {
        return asset.balanceOf(address(this));
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (style) {
            // transfer shares into this contract
            asset.safeTransferFrom(msg.sender, address(this), assets);

            asset.safeApprove(msg.sender, assets);

            // Try to re-enter into cellar via deposit
            ERC4626(msg.sender).deposit(assets, receiver);

            // This return should never be hit because the above deposit calls fails from re-entrancy.
            return 0;
        } else {
            Cellar cellar = Cellar(msg.sender);
            stdstore.target(address(cellar)).sig(cellar.totalSupply.selector).checked_write(cellar.totalSupply() + 1);
            return 0;
        }
    }
}
