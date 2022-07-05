// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/**
 * @notice Partial interface for a Balancer Exchange Proxy contract
 **/
interface IBalancerExchangeProxy {
    struct Swap {
        address pool;
        address tokenIn;
        address tokenOut;
        uint    swapAmount; // tokenInAmount / tokenOutAmount
        uint    limitReturnAmount; // minAmountOut / maxAmountIn
        uint    maxPrice;
    }

    /**
     * @notice Execute multi-hop swaps returned from off-chain Smart Order Router (SOR) for swapExactIn trade type
     * @param swapSequences Swap sequences
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @param totalAmountIn The amount of input tokens to send
     * @param minTotalAmountOut The minimum amount of output tokens that must be received for the transaction not to revert
     * @return totalAmountOut The amount of output tokens
     **/
    function multihopBatchSwapExactIn(
        Swap[][] memory swapSequences,
        TokenInterface tokenIn,
        TokenInterface tokenOut,
        uint totalAmountIn,
        uint minTotalAmountOut
    ) external payable returns (uint totalAmountOut);

    /**
     * @notice View function that calculates most optimal swaps (exactIn swap type) across a max of nPools
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @param swapAmount tokenInAmount / tokenOutAmount
     * @param nPools number of pools
     * @return swaps an array of Swaps
     * @return totalOutput the total amount out for swap
     **/
    function viewSplitExactIn(
        address tokenIn,
        address tokenOut,
        uint swapAmount,
        uint nPools
    ) external view returns (Swap[] memory swaps, uint totalOutput);
}

interface TokenInterface {
    function balanceOf(address) external view returns (uint);
    function allowance(address, address) external view returns (uint);
    function approve(address, uint) external returns (bool);
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
    function deposit() external payable;
    function withdraw(uint) external;
}

interface PoolInterface {
    function swapExactAmountIn(address, uint, address, uint, uint) external returns (uint, uint);
    function swapExactAmountOut(address, uint, address, uint, uint) external returns (uint, uint);
    function calcInGivenOut(uint, uint, uint, uint, uint, uint) external pure returns (uint);
    function calcOutGivenIn(uint, uint, uint, uint, uint, uint) external pure returns (uint);
    function getDenormalizedWeight(address) external view returns (uint);
    function getBalance(address) external view returns (uint);
    function getSwapFee() external view returns (uint);
}
