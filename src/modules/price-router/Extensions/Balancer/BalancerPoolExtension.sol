// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IVault, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";

/**
 * @title Sommelier Price Router Balancer Linear Pool Extension
 * @notice Allows the Price Router to price Balancer Linear pool BPTs.
 * @author crispymangoes
 */
abstract contract BalancerPoolExtension is Extension {
    /**
     * @notice Attempted to price BPTs while in the Balancer Vault.
     */
    error BalancerPoolExtension__Reentrancy();

    /**
     * @notice The Balancer Vault
     */
    IVault public immutable balancerVault;

    constructor(PriceRouter _priceRouter, IVault _balancerVault) Extension(_priceRouter) {
        balancerVault = _balancerVault;
    }

    /**
     * @dev Ensure we are not in a Vault context when this function is called, by attempting a no-op internal
     * balance operation. If we are already in a Vault transaction (e.g., a swap, join, or exit), the Vault's
     * reentrancy protection will cause this function to revert.
     *
     * The exact function call doesn't really matter: we're just trying to trigger the Vault reentrancy check
     * (and not hurt anything in case it works). An empty operation array with no specific operation at all works
     * for that purpose, and is also the least expensive in terms of gas and bytecode size.
     *
     * Call this at the top of any function that can cause a state change in a pool and is either public itself,
     * or called by a public function *outside* a Vault operation (e.g., join, exit, or swap).
     *
     * If this is *not* called in functions that are vulnerable to the read-only reentrancy issue described
     * here (https://forum.balancer.fi/t/reentrancy-vulnerability-scope-expanded/4345), those functions are unsafe,
     * and subject to manipulation that may result in loss of funds.
     */
    function _ensureNotInVaultContext(IVault vault) internal view {
        // Perform the following operation to trigger the Vault's reentrancy guard.
        // Use a static call so that it can be a view function (even though the
        // function is non-view).
        //
        // IVault.UserBalanceOp[] memory noop = new IVault.UserBalanceOp[](0);
        // _vault.manageUserBalance(noop);

        // solhint-disable-next-line var-name-mixedcase
        bytes32 REENTRANCY_ERROR_HASH = keccak256(abi.encodeWithSignature("Error(string)", "BAL#400"));

        // read-only re-entrancy protection - this call is always unsuccessful but we need to make sure
        // it didn't fail due to a re-entrancy attack
        (, bytes memory revertData) = address(vault).staticcall(
            abi.encodeWithSelector(vault.manageUserBalance.selector, new address[](0))
        );

        if (keccak256(revertData) == REENTRANCY_ERROR_HASH) revert BalancerPoolExtension__Reentrancy();
    }
}
