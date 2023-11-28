// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { ISolver } from "./ISolver.sol";

// TODO remove
import { console } from "@forge-std/Test.sol";

contract WithdrawQueue is ReentrancyGuard {
    using SafeTransferLib for ERC4626;
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Math for uint128;

    // ========================================= STRUCTS =========================================

    struct SolveData {
        ERC20 asset;
        uint8 assetDecimals;
        uint8 shareDecimals;
    }

    // TODO allow users to set a trusted solver?
    struct WithdrawRequest {
        uint64 deadline; // deadline to fulfill request
        bool inSolve; // Inidicates whether this user is currently having their request fulfilled.
        uint88 executionSharePrice; // In terms of asset decimals
        uint96 sharesToWithdraw; // The amount of shares the user wants to redeem.
    }

    // ========================================= CONSTANTS =========================================

    // ========================================= GLOBAL STATE =========================================
    mapping(address => mapping(ERC4626 => WithdrawRequest)) public userWithdrawRequest;
    //============================== ERRORS ===============================

    error WithdrawQueue__UserRepeated();
    error WithdrawQueue__RequestDeadlineExceeded();
    error WithdrawQueue__UserNotInSolve();
    error WithdrawQueue__NoShares();

    //============================== EVENTS ===============================

    event RequestUpdated(
        address user,
        address share,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );
    event RequestFulfilled(address user, address share, uint256 sharesSpent, uint256 assetsReceived, uint256 timestamp);

    //============================== IMMUTABLES ===============================

    constructor() {}

    //============================== USER FUNCTIONS ===============================

    function getUserWithdrawRequest(address user, ERC4626 share) external view returns (WithdrawRequest memory) {
        return userWithdrawRequest[user][share];
    }

    function isWithdrawRequestValid(ERC4626 share, WithdrawRequest calldata userRequest) external view returns (bool) {
        // Validate amount.
        if (userRequest.sharesToWithdraw > share.balanceOf(msg.sender)) return false;
        // Validate deadline.
        if (block.timestamp > userRequest.deadline) return false;
        // Validate approval.
        if (share.allowance(msg.sender, address(this)) < userRequest.sharesToWithdraw) return false;

        if (userRequest.sharesToWithdraw == 0) return false;

        if (userRequest.executionSharePrice == 0) return false;

        return true;
    }

    // TODO there is a front running attack like the ERC20 approval attack
    // User already has a non zero request, they submit a TX to increase it
    // Attacker sees it, front runs it, solves it, then lets users TX goes through and solves again.
    function updateWithdrawRequest(ERC4626 share, WithdrawRequest calldata userRequest) external nonReentrant {
        WithdrawRequest storage request = userWithdrawRequest[msg.sender][share];

        request.deadline = userRequest.deadline;
        request.executionSharePrice = userRequest.executionSharePrice;
        request.sharesToWithdraw = userRequest.sharesToWithdraw;

        // Emit full amount user has.
        emit RequestUpdated(
            msg.sender,
            address(share),
            userRequest.sharesToWithdraw,
            userRequest.deadline,
            userRequest.executionSharePrice,
            block.timestamp
        );
    }

    //============================== SOLVER FUNCTIONS ===============================

    function solve(
        ERC4626 share,
        address[] calldata users,
        bytes calldata runData,
        address solver
    ) external nonReentrant {
        // Get Solve Data.
        SolveData memory solveData;
        solveData.asset = share.asset();
        solveData.assetDecimals = solveData.asset.decimals();
        solveData.shareDecimals = share.decimals();

        uint256 sharesToSolver;
        uint256 requiredAssets;
        for (uint256 i; i < users.length; ++i) {
            WithdrawRequest storage request = userWithdrawRequest[users[i]][share];

            if (request.inSolve) revert WithdrawQueue__UserRepeated();
            if (block.timestamp > request.deadline) revert WithdrawQueue__RequestDeadlineExceeded();
            if (request.sharesToWithdraw == 0) revert WithdrawQueue__NoShares();

            // User gets whatever their execution share price is.
            requiredAssets += _calculateAssetAmount(
                request.sharesToWithdraw,
                request.executionSharePrice,
                solveData.shareDecimals
            );

            // If all checks above passed, the users request is valid and should be fulfilled.
            sharesToSolver += request.sharesToWithdraw;
            request.inSolve = true;
            // Transfer shares from user to solver.
            share.safeTransferFrom(users[i], solver, request.sharesToWithdraw);
            continue;
        }

        ISolver(solver).finishSolve(runData, sharesToSolver, requiredAssets);

        for (uint256 i; i < users.length; ++i) {
            WithdrawRequest storage request = userWithdrawRequest[users[i]][share];

            if (request.inSolve) {
                // We know that the minimum price and deadline arguments are satisfied since this can only be true if they were.

                // Send user their share of assets.
                uint256 assetsToUser = _calculateAssetAmount(
                    request.sharesToWithdraw,
                    request.executionSharePrice,
                    solveData.shareDecimals
                );

                solveData.asset.safeTransferFrom(solver, users[i], assetsToUser);

                emit RequestFulfilled(
                    users[i],
                    address(share),
                    request.sharesToWithdraw,
                    assetsToUser,
                    block.timestamp
                );

                // Set shares to withdraw to 0.
                request.sharesToWithdraw = 0;
                request.inSolve = false;
            } else revert WithdrawQueue__UserNotInSolve();
        }
    }

    //============================== INTERNAL FUNCTIONS ===============================

    function _calculateAssetAmount(uint256 shares, uint256 price, uint8 shareDecimals) internal pure returns (uint256) {
        return price.mulDivDown(shares, 10 ** shareDecimals);
    }
}
