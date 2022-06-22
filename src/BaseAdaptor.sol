// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { PriceRouter } from "./PriceRouter.sol";

abstract contract BaseAdaptor {
    function getPricingInformation(address baseAsset) external view virtual returns (uint256 price, uint256 timestamp);

    function getPriceRange(address baseAsset) public view virtual returns (uint256 min, uint256 max);

    function getPriceWithDenomination(address baseAsset, address denomination)
        public
        view
        virtual
        returns (uint256 price, uint256 timestamp);
}
