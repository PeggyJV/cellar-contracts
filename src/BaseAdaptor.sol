// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { OracleRouter } from "./OracleRouter.sol";

abstract contract BaseAdaptor {
    function getPricingInformation(address baseAsset)
        external
        view
        virtual
        returns (OracleRouter.PricingInformation memory info);
}
