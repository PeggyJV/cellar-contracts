// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20Adaptor} from "src/modules/adaptors/ERC20Adaptor.sol";

/**
 * @title ERC20 Withdrawal Recovery Adaptor
 * @notice Isolates recovery ERC20 positions from positions that use the standard ERC20 adaptor identifier.
 */
contract ERC20WithdrawalRecoveryAdaptor is ERC20Adaptor {
    /**
     * @dev Identifier unique to withdrawal recovery positions in a shared registry.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("ERC20 Adaptor Withdrawal Recovery Candidate V 1.0"));
    }
}
