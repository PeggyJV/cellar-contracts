// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function abs(int256 n) internal pure returns (uint256) {
        return uint256(n >= 0 ? n : -n);
    }
}