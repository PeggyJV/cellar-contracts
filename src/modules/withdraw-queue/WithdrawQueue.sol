// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { ISolver } from "./ISolver.sol";

/**
 * @title WithdrawQueue
 * @notice Allows users to exit ERC4626 positions by offloading complex withdraws to 3rd party solvers.
 * @author crispymangoes
 */
contract WithdrawQueue is ReentrancyGuard {
    using SafeTransferLib for ERC4626;
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Math for uint128;

    // ========================================= STRUCTS =========================================

    /**
     * @notice Stores request information needed to fulfill a users withdraw request.
     * @param deadline unix timestamp for when request is no longer valid
     * @param executionSharePrice the share price in terms of share.asset() the user wants their shares "sold" at
     * @param sharesToWithdraw the amount of shares the user wants withdrawn
     * @param inSolve bool used during solves to prevent duplicate users, and to prevent redoing multiple checks
     */
    struct WithdrawRequest {
        uint64 deadline; // deadline to fulfill request
        uint88 executionSharePrice; // In terms of asset decimals
        uint96 sharesToWithdraw; // The amount of shares the user wants to redeem.
        bool inSolve; // Inidicates whether this user is currently having their request fulfilled.
    }

    /**
     * @notice Used in `viewSolveMetaData` helper function to return data in a clean struct.
     * @param user the address of the user
     * @param flags 8 bits indicating the state of the user only the first 4 bits are used XXXX0000
     *              Either all flags are false(user is solvable) or only 1 is true(an error occurred).
     *              From right to left
     *              - 0: indicates user deadline has passed.
     *              - 1: indicates user request has zero share amount.
     *              - 2: indicates user does not have enough shares in wallet.
     *              - 3: indicates user has not given WithdrawQueue approval.
     * @param sharesToSolve the amount of shares to solve
     * @param requiredAssets the amount of assets users wants for their shares
     */
    struct SolveMetaData {
        address user;
        uint8 flags;
        uint256 sharesToSolve;
        uint256 requiredAssets;
    }

    /**
     * @notice Used to reduce the number of local variables in `solve`.
     */
    struct SolveData {
        ERC20 asset;
        uint8 assetDecimals;
        uint8 shareDecimals;
    }

    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice Maps user address to share to a WithdrawRequest struct.
     */
    mapping(address => mapping(ERC4626 => WithdrawRequest)) public userWithdrawRequest;

    //============================== ERRORS ===============================

    error WithdrawQueue__UserRepeated(address user);
    error WithdrawQueue__RequestDeadlineExceeded(address user);
    error WithdrawQueue__UserNotInSolve(address user);
    error WithdrawQueue__NoShares(address user);

    //============================== EVENTS ===============================

    /**
     * @notice Emitted when `updateWithdrawRequest` is called.
     */
    event RequestUpdated(
        address user,
        address share,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );

    /**
     * @notice Emitted when `solve` exchanges a users shares for the underlying asset.
     */
    event RequestFulfilled(address user, address share, uint256 sharesSpent, uint256 assetsReceived, uint256 timestamp);

    //============================== IMMUTABLES ===============================

    constructor() {}

    //============================== USER FUNCTIONS ===============================

    /**
     * @notice Get a users Withdraw Request.
     */
    function getUserWithdrawRequest(address user, ERC4626 share) external view returns (WithdrawRequest memory) {
        return userWithdrawRequest[user][share];
    }

    /**
     * @notice Helper function that returns either
     *         true: Withdraw request is valid.
     *         false: Withdraw request is not valid.
     * @dev It is possible for a withdraw request to return false from this function, but using the
     *      request in `updateWithdrawRequest` will succeed, but solvers will not be able to include
     *      the user in `solve` unless some other state is changed.
     */
    function isWithdrawRequestValid(
        ERC4626 share,
        address user,
        WithdrawRequest calldata userRequest
    ) external view returns (bool) {
        // Validate amount.
        if (userRequest.sharesToWithdraw > share.balanceOf(user)) return false;
        // Validate deadline.
        if (block.timestamp > userRequest.deadline) return false;
        // Validate approval.
        if (share.allowance(user, address(this)) < userRequest.sharesToWithdraw) return false;
        // Validate sharesToWithdraw is nonzero.
        if (userRequest.sharesToWithdraw == 0) return false;
        // Validate sharesToWithdraw is nonzero.
        if (userRequest.executionSharePrice == 0) return false;

        return true;
    }

    /**
     * @notice Allows user to add/update their withdraw request.
     * @notice It is possible for a withdraw request with a zero executionSharePrice to be made, and solved.
     *         If this happens, users will be selling their shares for no assets in return.
     *         To determine a safe executionSharePrice, share.previewRedeem should be used to get
     *         a good share price, then the user can lower it from there to make their request fill faster.
     */
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

    /**
     * @notice Called by solvers in order to exchange shares for share.asset().
     * @dev It is very likely `solve` TXs will be front run if broadcasted to public mem pools,
     *      so solvers should use private mem pools.
     */
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

            if (request.inSolve) revert WithdrawQueue__UserRepeated(users[i]);
            if (block.timestamp > request.deadline) revert WithdrawQueue__RequestDeadlineExceeded(users[i]);
            if (request.sharesToWithdraw == 0) revert WithdrawQueue__NoShares(users[i]);

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
        }

        ISolver(solver).finishSolve(runData, msg.sender, sharesToSolver, requiredAssets);

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
            } else revert WithdrawQueue__UserNotInSolve(users[i]);
        }
    }

    /**
     * @notice Helper function solvers can use to determine if users are solvable, and the required amounts to do so.
     * @notice Repeated users are not accounted for in this setup, so if solvers have repeat users in their `users`
     *         array the results can be wrong.
     */
    function viewSolveMetaData(
        ERC4626 share,
        address[] calldata users
    ) external view returns (SolveMetaData[] memory metaData, uint256 totalRequiredAssets, uint256 totalSharesToSolve) {
        // Get Solve Data.
        SolveData memory solveData;
        solveData.asset = share.asset();
        solveData.assetDecimals = solveData.asset.decimals();
        solveData.shareDecimals = share.decimals();

        // Setup meta data.
        metaData = new SolveMetaData[](users.length);

        for (uint256 i; i < users.length; ++i) {
            WithdrawRequest memory request = userWithdrawRequest[users[i]][share];

            metaData[i].user = users[i];

            if (block.timestamp > request.deadline) {
                metaData[i].flags |= uint8(1);
            }
            if (request.sharesToWithdraw == 0) {
                metaData[i].flags |= uint8(1) << 1;
            }
            if (share.balanceOf(users[i]) < request.sharesToWithdraw) {
                metaData[i].flags |= uint8(1) << 2;
            }
            if (share.allowance(users[i], address(this)) < request.sharesToWithdraw) {
                metaData[i].flags |= uint8(1) << 3;
            }

            metaData[i].sharesToSolve = request.sharesToWithdraw;

            // User gets whatever their execution share price is.
            uint256 userAssets = _calculateAssetAmount(
                request.sharesToWithdraw,
                request.executionSharePrice,
                solveData.shareDecimals
            );
            metaData[i].requiredAssets = userAssets;

            // If flags is zero, no errors occurred.
            if (metaData[i].flags == 0) {
                totalRequiredAssets += userAssets;
                totalSharesToSolve += request.sharesToWithdraw;
            }
        }
    }

    //============================== INTERNAL FUNCTIONS ===============================

    /**
     * @notice Helper function to calculate the amount of assets a user is owed based off their shares, and execution price.
     */
    function _calculateAssetAmount(uint256 shares, uint256 price, uint8 shareDecimals) internal pure returns (uint256) {
        return price.mulDivDown(shares, 10 ** shareDecimals);
    }
}
