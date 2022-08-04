// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

/**
 * @notice Partial interface for a Curve Registry Exchanges contract
 * @dev The registry exchange contract is used to find pools and query exchange rates for token swaps.
 *      It also provides a unified exchange API that can be useful for on-chain integrators.
 **/
interface ICurveSwaps {
    /**
     * @notice Perform up to four swaps in a single transaction
     * @dev Routing and swap params must be determined off-chain. This
     *      functionality is designed for gas efficiency over ease-of-use.
     * @param _route Array of [initial token, pool, token, pool, token, ...]
     *               The array is iterated until a pool address of 0x00, then the last
     *               given token is transferred to `_receiver` (address to transfer the final output token to)
     * @param _swap_params Multidimensional array of [i, j, swap type] where i and j are the correct
     *                     values for the n'th pool in `_route`. The swap type should be 1 for
     *                     a stableswap `exchange`, 2 for stableswap `exchange_underlying`, 3
     *                     for a cryptoswap `exchange`, 4 for a cryptoswap `exchange_underlying`
     *                     and 5 for Polygon factory metapools `exchange_underlying`
     * @param _expected The minimum amount received after the final swap.
     * @return Received amount of final output token
     **/
    function exchange_multiple(
        address[9] memory _route,
        uint256[3][4] memory _swap_params,
        uint256 _amount,
        uint256 _expected
    ) external returns (uint256);
}
