// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface ISolver {
    function finishSolve(bytes calldata runData, uint256 sharesReceived, uint256 assetApprovalAmount) external;
}

contract WithdrawQueue {
    using SafeTransferLib for ERC4626;
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Math for uint128;

    bool public locked;

    modifier nonReentrant() {
        require(!locked, "REENTRANCY");

        locked = true;

        _;

        locked = false;
    }

    struct UserData {
        uint64 deadline; // Once passed, users balance can be sent back to them by solvers, for a small fee.
        uint128 amount;
        uint64 minPrice; // In terms of hundredths of a bip 1e6 == 100%
    }

    // Stores users data based off ERC20 share
    mapping(address => mapping(ERC4626 => UserData)) public userData;

    // Stores fee based off ERC4626 share
    mapping(ERC4626 => uint256) public shareFee;

    event NewDeposit(address user, uint256 amount, uint256 deadline, uint256 minPrice);

    // This will overwrite existing setttings
    function deposit(ERC4626 share, UserData calldata newData) external nonReentrant {
        // Transfer shares in.
        share.safeTransferFrom(msg.sender, address(this), newData.amount);
        UserData storage data = userData[msg.sender][share];

        data.deadline = newData.deadline;
        data.minPrice = newData.minPrice;

        data.amount += newData.amount;

        // Emit full amount user has.
        emit NewDeposit(msg.sender, data.amount, newData.deadline, newData.minPrice);
    }

    // TODO need to check for reentrancy because I think if a solver were to re-enter and withdraw while solving, then
    // they would be able to withdraw their shares, and also "redeem" someone elses shares but take them.
    function withdraw(ERC4626 share, uint128 amount) external nonReentrant {
        UserData storage data = userData[msg.sender][share];

        // Underflow is desired.
        data.amount -= amount;

        share.safeTransfer(msg.sender, amount);
    }

    function solve(ERC4626 share, address[] calldata users, bytes calldata runData) external nonReentrant {
        // Determine the required amount of share.asset() solver must provide.
        ERC20 asset = share.asset();
        uint256 fee = shareFee[share];
        uint256 minExecutionSharePrice = share.previewRedeem(10 ** share.decimals()).mulDivDown(1e6 - fee, 1e6);

        // Determine how many shares should be sent to solver.
        uint256 sharesToSolver;
        uint256 feeSharesToSolver;
        for (uint256 i; i < users.length; ++i) {
            UserData memory data = userData[users[i]][share];

            if (minExecutionSharePrice >= data.minPrice && (data.deadline == 0 || data.deadline > block.timestamp)) {
                sharesToSolver += data.amount;
            } else if (data.deadline < block.timestamp) {
                // Add auto cancel fee to feeSharesToSolver.
                feeSharesToSolver += data.amount.mulDivDown(fee, 1e6);
            }
        }

        uint256 requiredAssets = minExecutionSharePrice.mulDivDown(sharesToSolver, 10 ** share.decimals());

        // Optimistically transfer shares to solver.
        share.safeTransfer(msg.sender, sharesToSolver + feeSharesToSolver);

        ISolver(msg.sender).finishSolve(runData, sharesToSolver + feeSharesToSolver, requiredAssets);

        for (uint256 i; i < users.length; ++i) {
            UserData storage data = userData[users[i]][share];

            if (data.deadline != 0 && data.deadline < block.timestamp) {
                // We have passed users deadline, so transfer their shares back to them minus the fee.
                share.safeTransfer(users[i], data.amount.mulDivDown(1e6 - fee, 1e6));
                // delete data; // gas refund
                delete data.amount;
                delete data.minPrice;
                delete data.deadline;

                // TODO emit event
            } else if (minExecutionSharePrice >= data.minPrice) {
                // Send user their share of assets.
                uint256 amount = requiredAssets.mulDivDown(data.amount, sharesToSolver);
                asset.safeTransferFrom(msg.sender, users[i], amount);
                // delete data;
                delete data.amount;
                delete data.minPrice;
                delete data.deadline;
                // TODO emit event
            }
            // Else there is nothing to do, this user deadline was not triggered, and the execution price was too low.

            if (minExecutionSharePrice >= data.minPrice && (data.deadline == 0 || data.deadline > block.timestamp)) {
                sharesToSolver += data.amount;
            }
        }
    }
}
