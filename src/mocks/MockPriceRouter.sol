// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockExchange } from "src/mocks/MockExchange.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "src/utils/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract MockPriceRouter {
    using Math for uint256;

    mapping(ERC20 => mapping(ERC20 => uint256)) public getExchangeRate;

    mapping(ERC20 => bool) public isSupported;

    function multicall(bytes[] calldata data) external view returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionStaticCall(address(this), data[i]);
        }
        return results;
    }

    function setExchangeRate(
        ERC20 baseAsset,
        ERC20 quoteAsset,
        uint256 exchangeRate
    ) external {
        getExchangeRate[baseAsset][quoteAsset] = exchangeRate;
    }

    function getValues(
        ERC20[] memory baseAssets,
        uint256[] memory amounts,
        ERC20 quoteAsset
    ) external view returns (uint256 value) {
        for (uint256 i; i < baseAssets.length; i++) value += getValue(baseAssets[i], amounts[i], quoteAsset);
    }

    function getValue(
        ERC20 baseAsset,
        uint256 amount,
        ERC20 quoteAsset
    ) public view returns (uint256 value) {
        value = amount.mulDivDown(getExchangeRate[baseAsset][quoteAsset], 10**baseAsset.decimals());
    }

    function supportAsset(ERC20 asset) external {
        isSupported[asset] = true;
    }
}
