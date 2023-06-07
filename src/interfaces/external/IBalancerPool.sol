// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IBalancerPool {
    function getMainToken() external view returns (address);

    function getRate() external view returns (uint256);

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
}
