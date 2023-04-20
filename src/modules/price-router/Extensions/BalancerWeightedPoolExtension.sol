// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IVault, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";
import { IBalancerPool } from "src/interfaces/external/IBalancerPool.sol";

import { console } from "@forge-std/Test.sol";

contract BalancerWeightedPoolExtension is Extension {
    using Math for uint256;

    IVault public immutable balancerVault;

    constructor(PriceRouter _priceRouter, IVault _balancerVault) Extension(_priceRouter) {
        balancerVault = _balancerVault;
    }

    /**
     * @notice Aave Derivative Storage
     */
    mapping(ERC20 => bytes32) public getBalancerWeightedPoolDerivativeStorage;

    function setupSource(ERC20 asset, bytes memory) external override onlyPriceRouter {
        // asset is a balancer LP token
        IBalancerPool pool = IBalancerPool(address(asset));
        bytes32 poolId = pool.getPoolId();
        (IERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);

        // Make sure we can price all underlying tokens.
        for (uint256 i; i < tokens.length; ++i)
            if (!priceRouter.isSupported(ERC20(address(tokens[i])))) revert("tokens must be supported.");

        // TODO we could save the poolId and tokens in this contract for less state reads
        getBalancerWeightedPoolDerivativeStorage[asset] = poolId;
    }

    // TODO this might need to return the cache
    function getPriceInUSD(
        ERC20 asset,
        PriceRouter.PriceCache[PRICE_CACHE_SIZE] memory cache
    ) external view override returns (uint256) {
        _ensureNotInVaultContext(balancerVault);
        IBalancerPool pool = IBalancerPool(address(asset));

        bytes32 poolId = getBalancerWeightedPoolDerivativeStorage[asset];
        (IERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);

        uint256 tokenLength = tokens.length;
        uint256[] memory weights = pool.getNormalizedWeights();

        if (tokenLength != weights.length) revert("Length Mismatch");

        // TODO can we safely use last invariant to save gas, and see if we can find actualTotalSupply()
        uint256 priceBpt = uint256(10 ** pool.decimals()).mulDivDown(pool.getInvariant(), pool.totalSupply());

        for (uint256 i; i < tokenLength; ++i) {
            ERC20 token = ERC20(address(tokens[i]));
            // Get price from price router.
            uint256 price = priceRouter.extensionGetPriceInUSD(token, cache);
            console.log("Price", price);
            console.log("Weights", weights[i]);
            priceBpt = priceBpt * (price.mulDivDown(1e18, weights[i])) ** weights[i];
            console.log("Price BPT", priceBpt);
        }
        console.log("Here");

        return priceBpt;
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

        if (keccak256(revertData) == REENTRANCY_ERROR_HASH) revert("Reentrancy");
    }
}
