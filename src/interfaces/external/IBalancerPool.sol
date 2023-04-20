// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IBalancerPool {
    function getInvariant() external view returns (uint256);

    function getLastInvariant() external view returns (uint256);

    function getFinalTokens() external view returns (address[] memory);

    function getNormalizedWeight(address token) external view returns (uint256);

    function getNormalizedWeights() external view returns (uint256[] memory);

    function getSwapFee() external view returns (uint256);

    function getNumTokens() external view returns (uint256);

    function getBalance(address token) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function getPoolId() external view returns (bytes32);

    function decimals() external view returns (uint8);

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn) external;

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountIn, uint256 spotPriceAfter);

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external returns (uint256 poolAmountOut);

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut) external;

    function exitswapExternAmountOut(
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPoolAmountIn
    ) external returns (uint256 poolAmountIn);
}
