// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAaveToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
