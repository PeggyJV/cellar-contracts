// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract MockPriceOracle {
    mapping(address => uint256) public getLatestPrice;

    function setPrice(address token, uint256 price) external {
        getLatestPrice[token] = price;
    }
}
