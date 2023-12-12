// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

interface ISolver {
    function finishSolve(
        bytes calldata runData,
        address initiator,
        uint256 sharesReceived,
        uint256 assetApprovalAmount
    ) external;
}
