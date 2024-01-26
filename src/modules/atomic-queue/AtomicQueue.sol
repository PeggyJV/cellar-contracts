// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { IAtomicSolver } from "./IAtomicSolver.sol";

/**
 * @title AtomicQueue
 * @notice Allows users to create `AtomicRequests` that specify an ERC20 asset to `give`
 *         and an ERC20 asset to `take` in return.
 * @author crispymangoes
 */
contract AtomicQueue is ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    // ========================================= STRUCTS =========================================

    /**
     * @notice Stores request information needed to fulfill a users atomic request.
     * @param deadline unix timestamp for when request is no longer valid
     * @param atomicPrice the price in terms of `take` asset the user wants their `give` assets "sold" at
     * @param giveAmount the amount of `give` asset the user wants converted to `take` asset
     * @param inSolve bool used during solves to prevent duplicate users, and to prevent redoing multiple checks
     */
    struct AtomicRequest {
        uint64 deadline; // deadline to fulfill request
        uint88 atomicPrice; // In terms of take asset decimals
        uint96 giveAmount; // The amount of give asset the user wants to sell.
        bool inSolve; // Inidicates whether this user is currently having their request fulfilled.
    }

    /**
     * @notice Used in `viewSolveMetaData` helper function to return data in a clean struct.
     * @param user the address of the user
     * @param flags 8 bits indicating the state of the user only the first 4 bits are used XXXX0000
     *              Either all flags are false(user is solvable) or only 1 is true(an error occurred).
     *              From right to left
     *              - 0: indicates user deadline has passed.
     *              - 1: indicates user request has zero give amount.
     *              - 2: indicates user does not have enough shares in wallet.
     *              - 3: indicates user has not given AtomicQueue approval.
     * @param giveToSolve the amount of give asset to solve
     * @param assetsToTake the amount of take assets users wants for their give assets
     */
    struct SolveMetaData {
        address user;
        uint8 flags;
        uint256 assetsToGive;
        uint256 assetsToTake;
    }

    /**
     * @notice Used to reduce the number of local variables in `solve`.
     */
    struct SolveData {
        uint8 takeDecimals;
        uint8 giveDecimals;
    }

    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice Maps user address to give asset to take asset to a AtomicRequest struct.
     */
    mapping(address => mapping(ERC20 => mapping(ERC20 => AtomicRequest))) public userAtomicRequest;

    //============================== ERRORS ===============================

    error AtomicQueue__UserRepeated(address user);
    error AtomicQueue__RequestDeadlineExceeded(address user);
    error AtomicQueue__UserNotInSolve(address user);
    error AtomicQueue__ZeroGiveAmount(address user);

    //============================== EVENTS ===============================

    /**
     * @notice Emitted when `updateAtomicRequest` is called.
     */
    event AtomicRequestUpdated(
        address user,
        address give,
        address take,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );

    /**
     * @notice Emitted when `solve` exchanges a users shares for the underlying asset.
     */
    event AtomicRequestFulfilled(
        address user,
        address give,
        address take,
        uint256 sharesSpent,
        uint256 assetsReceived,
        uint256 timestamp
    );

    //============================== IMMUTABLES ===============================

    constructor() {}

    //============================== USER FUNCTIONS ===============================

    /**
     * @notice Get a users Withdraw Request.
     */
    function getUserAtomicRequest(address user, ERC20 give, ERC20 take) external view returns (AtomicRequest memory) {
        return userAtomicRequest[user][give][take];
    }

    /**
     * @notice Helper function that returns either
     *         true: Withdraw request is valid.
     *         false: Withdraw request is not valid.
     * @dev It is possible for a withdraw request to return false from this function, but using the
     *      request in `updateAtomicRequest` will succeed, but solvers will not be able to include
     *      the user in `solve` unless some other state is changed.
     */
    function isAtomicRequestValid(
        ERC20 give,
        address user,
        AtomicRequest calldata userRequest
    ) external view returns (bool) {
        // Validate amount.
        if (userRequest.giveAmount > give.balanceOf(user)) return false;
        // Validate deadline.
        if (block.timestamp > userRequest.deadline) return false;
        // Validate approval.
        if (give.allowance(user, address(this)) < userRequest.giveAmount) return false;
        // Validate giveAmount is nonzero.
        if (userRequest.giveAmount == 0) return false;
        // Validate atomicPrice is nonzero.
        if (userRequest.atomicPrice == 0) return false;

        return true;
    }

    /**
     * @notice Allows user to add/update their withdraw request.
     * @notice It is possible for a withdraw request with a zero atomicPrice to be made, and solved.
     *         If this happens, users will be selling their shares for no assets in return.
     *         To determine a safe atomicPrice, share.previewRedeem should be used to get
     *         a good share price, then the user can lower it from there to make their request fill faster.
     */
    function updateAtomicRequest(ERC20 give, ERC20 take, AtomicRequest calldata userRequest) external nonReentrant {
        AtomicRequest storage request = userAtomicRequest[msg.sender][give][take];

        request.deadline = userRequest.deadline;
        request.atomicPrice = userRequest.atomicPrice;
        request.giveAmount = userRequest.giveAmount;

        // Emit full amount user has.
        emit AtomicRequestUpdated(
            msg.sender,
            address(give),
            address(take),
            userRequest.giveAmount,
            userRequest.deadline,
            userRequest.atomicPrice,
            block.timestamp
        );
    }

    //============================== SOLVER FUNCTIONS ===============================

    /**
     * @notice Called by solvers in order to exchange give asset for take asset.
     * @notice Solvers are optimistically transferred the give asset, then are required to
     *         approve this contrac to spend enough of take assets to cover all requests.
     * @dev It is very likely `solve` TXs will be front run if broadcasted to public mem pools,
     *      so solvers should use private mem pools.
     */
    function solve(
        ERC20 give,
        ERC20 take,
        address[] calldata users,
        bytes calldata runData,
        address solver
    ) external nonReentrant {
        // Get Solve Data.
        SolveData memory solveData;
        solveData.takeDecimals = take.decimals();
        solveData.giveDecimals = give.decimals();

        uint256 assetsToGive;
        uint256 assetsToTake;
        for (uint256 i; i < users.length; ++i) {
            AtomicRequest storage request = userAtomicRequest[users[i]][give][take];

            if (request.inSolve) revert AtomicQueue__UserRepeated(users[i]);
            if (block.timestamp > request.deadline) revert AtomicQueue__RequestDeadlineExceeded(users[i]);
            if (request.giveAmount == 0) revert AtomicQueue__ZeroGiveAmount(users[i]);

            // User gets whatever their execution share price is.
            assetsToTake += _calculateAssetAmount(request.giveAmount, request.atomicPrice, solveData.giveDecimals);

            // If all checks above passed, the users request is valid and should be fulfilled.
            assetsToGive += request.giveAmount;
            request.inSolve = true;
            // Transfer shares from user to solver.
            give.safeTransferFrom(users[i], solver, request.giveAmount);
        }

        IAtomicSolver(solver).finishSolve(runData, msg.sender, give, take, assetsToGive, assetsToTake);

        for (uint256 i; i < users.length; ++i) {
            AtomicRequest storage request = userAtomicRequest[users[i]][give][take];

            if (request.inSolve) {
                // We know that the minimum price and deadline arguments are satisfied since this can only be true if they were.

                // Send user their share of assets.
                uint256 assetsToUser = _calculateAssetAmount(
                    request.giveAmount,
                    request.atomicPrice,
                    solveData.giveDecimals
                );

                take.safeTransferFrom(solver, users[i], assetsToUser);

                emit AtomicRequestFulfilled(
                    users[i],
                    address(give),
                    address(take),
                    request.giveAmount,
                    assetsToUser,
                    block.timestamp
                );

                // Set shares to withdraw to 0.
                request.giveAmount = 0;
                request.inSolve = false;
            } else revert AtomicQueue__UserNotInSolve(users[i]);
        }
    }

    /**
     * @notice Helper function solvers can use to determine if users are solvable, and the required amounts to do so.
     * @notice Repeated users are not accounted for in this setup, so if solvers have repeat users in their `users`
     *         array the results can be wrong.
     * @dev Since a user can have multiple requests with the same give asset but different take asset, it is
     *      possible for `viewSolveMetaData` to report no errors, but for a solve to fail, if any solves were done
     *      between the time `viewSolveMetaData` and before `solve` is called.
     */
    function viewSolveMetaData(
        ERC20 give,
        ERC20 take,
        address[] calldata users
    ) external view returns (SolveMetaData[] memory metaData, uint256 totalAssetsToTake, uint256 totalAssetsToGive) {
        // Get Solve Data.
        SolveData memory solveData;
        solveData.takeDecimals = take.decimals();
        solveData.giveDecimals = give.decimals();

        // Setup meta data.
        metaData = new SolveMetaData[](users.length);

        for (uint256 i; i < users.length; ++i) {
            AtomicRequest memory request = userAtomicRequest[users[i]][give][take];

            metaData[i].user = users[i];

            if (block.timestamp > request.deadline) {
                metaData[i].flags |= uint8(1);
            }
            if (request.giveAmount == 0) {
                metaData[i].flags |= uint8(1) << 1;
            }
            if (give.balanceOf(users[i]) < request.giveAmount) {
                metaData[i].flags |= uint8(1) << 2;
            }
            if (give.allowance(users[i], address(this)) < request.giveAmount) {
                metaData[i].flags |= uint8(1) << 3;
            }

            metaData[i].assetsToGive = request.giveAmount;

            // User gets whatever their execution share price is.
            uint256 userAssets = _calculateAssetAmount(request.giveAmount, request.atomicPrice, solveData.giveDecimals);
            metaData[i].assetsToTake = userAssets;

            // If flags is zero, no errors occurred.
            if (metaData[i].flags == 0) {
                totalAssetsToTake += userAssets;
                totalAssetsToGive += request.giveAmount;
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
