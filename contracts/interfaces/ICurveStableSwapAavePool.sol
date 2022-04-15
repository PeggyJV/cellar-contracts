// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

/**
 * @notice Partial interface for a Curve StableSwapAavePool contract
 **/
interface ICurveStableSwapAavePool {
    /**
     * @notice Performs an exchange between two wrapped coins (aTokens) using Curve StableSwap Aave Pool
     * @dev Index values can be found via the `coins` public getter method
     * @param i Index value for the wrapped coin (aToken) to send
     * @param j Index value of the wrapped coin (aToken) to receive
     * @param _dx Amount of `i` being exchanged
     * @param _min_dy Minimum amount of `j` to receive
     * @return Actual amount of `j` received
     */
    function exchange(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy
    ) external returns (uint256);

    /**
     * @notice Getter for the array of wrapped coins (aTokens) within the pool
     * @param i Index value for the wrapped coin (aToken)
     * @return The address of the wrapped coin (aToken)
     */
    function coins(uint256 i) external returns (address);

    /**
     * @notice Perform an exchange between two underlying tokens using Curve StableSwap Aave Pool
     * @dev Index values can be found via the `underlying_coins` public getter method
     * @param i Index value for the underlying coin to send
     * @param j Index value of the underlying coin to receive
     * @param _dx Amount of `i` being exchanged
     * @param _min_dy Minimum amount of `j` to receive
     * @return Actual amount of `j` received
     */
    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy
    ) external returns (uint256);

    /**
     * @notice Getter for the array of underlying coins within the pool
     * @param i index value for the underlying coin
     * @return the address of the underlying coin
     */
    function underlying_coins(uint256 i) external returns (address);
}

