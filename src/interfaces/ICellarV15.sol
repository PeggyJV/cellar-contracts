// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";

enum WithdrawType {
    ORDERLY,
    PROPORTIONAL
}

interface ICellarV15 {
    function rebalance(
        address to,
        address from,
        uint256 amount,
        SwapRouter.Exchange exchange,
        bytes memory params
    ) external;

    function setWithdrawType(WithdrawType wt) external;
}
