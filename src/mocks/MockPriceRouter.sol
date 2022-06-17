// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { MockExchange } from "./MockExchange.sol";

contract MockPriceRouter {
    MockExchange public exchange;

    constructor(MockExchange _exchange) {
        exchange = _exchange;
    }

    function getValue(
        ERC20[] memory baseAssets,
        uint256[] memory amounts,
        ERC20 quoteAsset
    ) external view returns (uint256 value) {
        for (uint256 i; i < baseAssets.length; i++) value += getValue(baseAssets[i], amounts[i], quoteAsset);
    }

    function getValue(
        ERC20 baseAsset,
        uint256 amounts,
        ERC20 quoteAsset
    ) public view returns (uint256) {
        return exchange.convert(address(baseAsset), address(quoteAsset), amounts);
    }

    function getExchangeRate(ERC20 baseAsset, ERC20 quoteAsset) external view returns (uint256) {
        return exchange.getExchangeRate(address(baseAsset), address(quoteAsset));
    }
}
