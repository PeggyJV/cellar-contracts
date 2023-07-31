// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { FTokenAdaptorV1, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptorV1.sol";

contract MockFTokenAdaptorV1 is FTokenAdaptorV1 {
    constructor(bool _accountForInterest, address frax) FTokenAdaptorV1(_accountForInterest, frax) {}

    //============================================ Interface Helper Functions ===========================================

    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Mock FraxLend fTokenV1 Adaptor V 0.0"));
    }
}
