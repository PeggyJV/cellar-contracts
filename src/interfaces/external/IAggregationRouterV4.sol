// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAggregationExecutor } from "src/interfaces/external/IAggregationExecutor.sol";

struct SwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
    bytes permit;
}

interface IAggregationRouterV4 {
    function swap(
        IAggregationExecutor caller,
        SwapDescription memory desc,
        bytes memory data
    )
        external
        returns (
            uint256 returnAmount,
            uint256 spentAmount,
            uint256 gasLeft
        );
}
