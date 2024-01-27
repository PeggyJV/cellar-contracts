// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface IAtomicSolver {
    function finishSolve(
        bytes calldata runData,
        address initiator,
        ERC20 give,
        ERC20 take,
        uint256 assetsToOffer,
        uint256 assetsForWant
    ) external;
}
