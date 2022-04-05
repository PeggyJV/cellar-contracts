// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import {MockStkAAVE} from "./MockStkAAVE.sol";

contract MockIncentivesController {
    MockStkAAVE public stkAAVE;
    mapping(address => uint256) public usersUnclaimedRewards;

    constructor(MockStkAAVE _stkAAVE) {
        stkAAVE = _stkAAVE;
    }

    /// @dev For testing purposes
    function addRewards(address account, uint256 amount) external {
        usersUnclaimedRewards[account] += amount;
    }

    function claimRewards(
        address[] calldata,
        uint256 amount,
        address to
    ) external returns (uint256) {
        uint256 claimable = usersUnclaimedRewards[to];

        if (amount > claimable) {
            amount = claimable;
        }

        usersUnclaimedRewards[to] -= amount;

        stkAAVE.mint(to, amount);

        return amount;
    }
}