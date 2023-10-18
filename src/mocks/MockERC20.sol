// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) {}

    function mint() external {
        _mint(msg.sender, 10_000 * (10 ** decimals));
    }
}
