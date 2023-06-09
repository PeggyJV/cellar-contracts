// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";

contract MockFTokenAdaptor is FTokenAdaptor {
    //============================================ Interface Helper Functions ===========================================

    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Mock FraxLend fToken Adaptor V 0.0"));
    }

    function ACCOUNT_FOR_INTEREST() internal pure override returns (bool) {
        return false;
    }
}
