// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface ICometRewards {
    function claim(address comet, address src, bool shouldAccrue) external;
}
