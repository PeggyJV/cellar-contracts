// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { PriceRouter } from "./PriceRouter.sol";

abstract contract BaseAdaptor {
    function getPricingInformation(address baseAsset)
        external
        view
        virtual
        returns (PriceRouter.PricingInformation memory info);
}
