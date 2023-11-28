// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ISolver } from "./ISolver.sol";

contract SimpleSolver is ISolver {
    // Simple solver implements a few common solving techniques.

    // TODO redeem, just redeem the shares for the underlying asset, only useful if redeem only returns cellar underlying asset.

    // TODO exchange, user wants to deposit, and is able to "buy" shares from users in the withdraw queue instead.

    function finishSolve(bytes calldata runData, uint256 sharesReceived, uint256 assetApprovalAmount) external {}
}
