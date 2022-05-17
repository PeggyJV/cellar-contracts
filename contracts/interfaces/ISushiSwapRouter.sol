// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/**
 * @notice Partial interface for a SushiSwap Router contract
 **/
interface ISushiSwapRouter {
    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible, along the route determined by the `path`
     * @dev The first element of `path` is the input token, the last is the output token,
     *      and any intermediate elements represent intermediate pairs to trade through (if, for example, a direct pair does not exist).
     *      `msg.sender` should have already given the router an allowance of at least `amountIn` on the input token
     * @param amountIn The amount of input tokens to send
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert
     * @param path An array of token addresses. `path.length` must be >= 2. Pools for each consecutive pair of addresses must exist and have liquidity
     * @param to Recipient of the output tokens
     * @param deadline Unix timestamp after which the transaction will revert
     * @return amounts The input token amount and all subsequent output token amounts
     **/
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    /**
     * @notice Given an output asset amount and an array of token addresses,
     * calculates all preceding minimum input token amounts by calling `getReserves`
     * for each pair of token addresses in the `path` in turn, and using these to call getAmountIn.
     * Useful for calculating optimal token amounts before calling swap.
     * @param amountOut The amount of output tokens that must be received
     * @param path An array of token addresses. `path.length` must be >= 2. Pools for each consecutive pair of addresses must exist and have liquidity
     * @return amounts The input token amount and all subsequent output token amounts
     **/
    function getAmountsIn(
        uint amountOut,
        address[] memory path
    ) external view returns (uint[] memory amounts);

    /**
     * @notice Given an input asset amount and an array of token addresses, 
     * calculates all subsequent maximum output token amounts by calling `getReserves`
     * for each pair of token addresses in the `path` in turn, and using these to call getAmountOut. 
     * Useful for calculating optimal token amounts before calling swap.
     * @param amountIn The amount of input tokens to send
     * @param path An array of token addresses. `path.length` must be >= 2. Pools for each consecutive pair of addresses must exist and have liquidity
     * @return amounts The input token amount and all subsequent output token amounts
     **/
    function getAmountsOut(
        uint amountIn,
        address[] memory path
    ) external view returns (uint[] memory amounts);
}
