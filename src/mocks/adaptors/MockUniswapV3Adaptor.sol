// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

contract MockUniswapV3Adaptor is UniswapV3Adaptor {
    /**
     * @notice Uniswap V3 Tracker on FORKED ETH Mainnet.
     */
    function tracker() internal pure override returns (UniswapV3PositionTracker) {
        return UniswapV3PositionTracker(0xa0Cb889707d426A7A386870A03bc70d1b0697598);
    }
}
