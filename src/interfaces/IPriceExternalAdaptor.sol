// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface IPriceExternalAdaptor {
    function getValueInUSDAndTimestamp(ERC20 asset) external view returns (uint256 price, uint256 timestamp);
}
