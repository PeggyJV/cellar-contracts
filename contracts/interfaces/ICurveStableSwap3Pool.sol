// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

/**
 * @notice Partial interface for a Curve StableSwap3Pool contract
 **/
interface ICurveStableSwap3Pool {
    /**
     * @notice Performs an exchange between two coins using Curve StableSwap 3Pool
     * @param i index value for the coin to send
     * @param j index value of the coin to receive
     * @param _dx amount of i being exchanged
     * @param _min_dy minimum amount of j to receive
     */
    function exchange(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy
    ) external;
    
    /**
     * @notice Getter for the array of swappable coins within the pool
     * @param i index value for the coin
     * @return the address of the coin
     */
    function coins(uint256 i) external returns (address);
}

