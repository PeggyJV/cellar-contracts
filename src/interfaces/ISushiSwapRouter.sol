// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

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
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
