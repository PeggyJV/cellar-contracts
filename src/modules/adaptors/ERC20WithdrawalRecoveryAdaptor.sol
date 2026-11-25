// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20Adaptor} from "src/modules/adaptors/ERC20Adaptor.sol";

/**
 * @title ERC20 Withdrawal Recovery Adaptor
 * @notice Isolates recovery ERC20 positions from positions that use the standard ERC20 adaptor identifier.
 * @dev WARNING: `balanceOf` reports the Cellar's full balance of the token, exactly like `ERC20Adaptor`.
 *      The distinct identifier lets the Registry trust a second position for a token that already has an
 *      `ERC20Adaptor` position, and `Cellar.addPosition` does not reject two positions for the same asset.
 *      A Cellar must never hold this position alongside an `ERC20Adaptor` position for the same token, or
 *      that token is counted twice in `totalAssets`. Replace the existing position; do not add beside it.
 */
contract ERC20WithdrawalRecoveryAdaptor is ERC20Adaptor {
    /**
     * @dev Identifier unique to withdrawal recovery positions in a shared registry.
     *      The string includes "Candidate" because it matches the deployed contract; changing it would change the
     *      identifier and no longer describe that deployment.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("ERC20 Adaptor Withdrawal Recovery Candidate V 1.0"));
    }
}
