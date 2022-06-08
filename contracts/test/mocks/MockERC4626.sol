// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC4626 } from "../../interfaces/ERC4626.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { MockERC20 } from "./MockERC20.sol";
import { MockWETH } from "./MockWETH.sol";

contract MockERC4626 is ERC4626 {
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        bool _assetIsETHInsteadOfWETH,
        address _weth
    ) ERC4626(_asset, _name, _symbol, _decimals, _assetIsETHInsteadOfWETH) {
        WETH = MockWETH(_weth);
    }

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    function burn(address from, uint256 value) external {
        _burn(from, value);
    }

    function simulateGain(uint256 assets, address receiver) external returns (uint256 shares) {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        MockERC20(address(asset)).mint(address(this), assets);

        _mint(receiver, shares);
    }

    function simulateLoss(uint256 assets) external {
        MockERC20(address(asset)).burn(address(this), assets);
    }

    function totalAssets() public view override returns (uint256) {
        if (address(asset) == address(WETH) && assetIsETHInsteadOfWETH) {
            return address(this).balance;
        } else {
            return asset.balanceOf(address(this));
        }
    }
}
