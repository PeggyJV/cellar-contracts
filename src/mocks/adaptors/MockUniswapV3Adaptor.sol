// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

contract MockUniswapV3Adaptor is UniswapV3Adaptor {
    constructor(address _positionManager, address _tracker) UniswapV3Adaptor(_positionManager, _tracker) {}
}
