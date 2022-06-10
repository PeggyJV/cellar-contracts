// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { WETH } from "@solmate/tokens/WETH.sol";

contract MockWETH is WETH {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        _burn(to, amount);
    }
}
