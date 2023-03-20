// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";

contract MockFeesAndReservesAdaptor is FeesAndReservesAdaptor {
    /**
     * @notice FeesAndReserves on FORKED ETH Mainnet.
     */
    function feesAndReserves() public pure override returns (FeesAndReserves) {
        return FeesAndReserves(0xa0Cb889707d426A7A386870A03bc70d1b0697598);
    }
}
