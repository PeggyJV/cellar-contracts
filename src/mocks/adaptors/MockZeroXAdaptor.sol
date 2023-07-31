// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";

contract MockZeroXAdaptor is ZeroXAdaptor {
    constructor(address _target) ZeroXAdaptor(_target) {}

    /**
     * @notice Override the ZeroX adaptors identifier so both adaptors can be added to the same registry.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Mock 0x Adaptor V 1.0"));
    }
}
