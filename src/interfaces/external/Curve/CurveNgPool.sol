// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface CurveNgPool {
    function ema_price() external view returns (uint256);

    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external payable;
}
