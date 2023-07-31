// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IVault, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";

/**
 * @title Sommelier Price Router Balancer Pool Extension
 * @notice Provides shared logic between Balancer Extensions.
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
    function ensureNotInVaultContext(IVault vault) internal view {
        // Perform the following operation to trigger the Vault's reentrancy guard:
        //
        // IVault.UserBalanceOp[] memory noop = new IVault.UserBalanceOp[](0);
        // _vault.manageUserBalance(noop);
        //
        // However, use a static call so that it can be a view function (even though the function is non-view).
        // This allows the library to be used more widely, as some functions that need to be protected might be
        // view.
        //
        // This staticcall always reverts, but we need to make sure it doesn't fail due to a re-entrancy attack.
        // Staticcalls consume all gas forwarded to them on a revert caused by storage modification.
        // By default, almost the entire available gas is forwarded to the staticcall,
        // causing the entire call to revert with an 'out of gas' error.
        //
        // We set the gas limit to 10k for the staticcall to
        // avoid wasting gas when it reverts due to storage modification.
        // `manageUserBalance` is a non-reentrant function in the Vault, so calling it invokes `_enterNonReentrant`
        // in the `ReentrancyGuard` contract, reproduced here:
        //
        //    function _enterNonReentrant() private {
        //        // If the Vault is actually being reentered, it will revert in the first line, at the `_require` that
        //        // checks the reentrancy flag, with "BAL#400" (corresponding to Errors.REENTRANCY) in the revertData.
        //        // The full revertData will be: `abi.encodeWithSignature("Error(string)", "BAL#400")`.
        //        _require(_status != _ENTERED, Errors.REENTRANCY);
        //
        //        // If the Vault is not being reentered, the check above will pass: but it will *still* revert,
        //        // because the next line attempts to modify storage during a staticcall. However, this type of
        //        // failure results in empty revertData.
        //        _status = _ENTERED;
        //    }
        //
        // So based on this analysis, there are only two possible revertData values: empty, or abi.encoded BAL#400.
        //
        // It is of course much more bytecode and gas efficient to check for zero-length revertData than to compare it
        // to the encoded REENTRANCY revertData.
        //
        // While it should be impossible for the call to fail in any other way (especially since it reverts before
        // `manageUserBalance` even gets called), any other error would generate non-zero revertData, so checking for
        // empty data guards against this case too.

        (, bytes memory revertData) = address(vault).staticcall{ gas: 10_000 }(
            abi.encodeWithSelector(vault.manageUserBalance.selector, 0)
        );

        if (revertData.length != 0) revert BalancerPoolExtension__Reentrancy();
    }
}
