// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

interface IPriceFeedAdaptor {
    function getPricingInformation(address baseAsset) external view returns (uint256 price, uint256 timestamp);

    function getPriceRange(address baseAsset) external view returns (uint128 min, uint128 max);

    function getPriceWithDenomination(address baseAsset, address denomination)
        external
        view
        returns (uint256 price, uint256 timestamp);
}
