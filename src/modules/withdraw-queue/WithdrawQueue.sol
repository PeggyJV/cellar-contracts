// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Owned } from "@solmate/auth/Owned.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { ISolver } from "./ISolver.sol";

// TODO remove
import { console } from "@forge-std/Test.sol";

contract WithdrawQueue is Owned, ReentrancyGuard {
    using SafeTransferLib for ERC4626;
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Math for uint128;

    // ========================================= STRUCTS =========================================

    struct ShareSettings {
        ERC20 asset;
        uint8 assetDecimals;
        uint8 shareDecimals;
        uint24 fee;
    }

    struct WithdrawRequest {
        uint64 deadline; // deadline to fulfill request
        uint24 maximumFee; // with 6 decimals of precision
        bool inSolve; // Inidicates whether this user is currently having their request fulfilled.
        uint32 minimumSharePrice; // With 4 decimals of precision
        uint128 sharesToWithdraw; // The amount of shares the user wants to redeem.
    }

    // ========================================= CONSTANTS =========================================

    // ========================================= GLOBAL STATE =========================================
    mapping(ERC4626 => ShareSettings) public shareSettings;
    mapping(address => mapping(ERC4626 => WithdrawRequest)) public userWithdrawRequest;
    //============================== ERRORS ===============================

    error WithdrawQueue__ShareAlreadyAdded();
    error WithdrawQueue__ShareNotAdded();
    error WithdrawQueue__MaxFeeforShareExceeded();
    error WithdrawQueue__BadAmount();
    error WithdrawQueue__BadDeadline();
    error WithdrawQueue__BadAllowance();
    error WithdrawQueue__BadMaximumFee();
    error WithdrawQueue__AssetChanged();
    error WithdrawQueue__AssetDecimalsChanged();
    error WithdrawQueue__ShareDecimalsChanged();
    error WithdrawQueue__UserRepeated();
    error WithdrawQueue__RequestDeadlineExceeded();
    error WithdrawQueue__RequestMaximumFeeExceeded();
    error WithdrawQueue__RequestMinimumSharePriceNotMet();
    error WithdrawQueue__UserNotInSolve();

    //============================== EVENTS ===============================

    event RequestUpdated(address user, uint256 amount, uint256 deadline, uint256 minPrice);
    event RequestFulfilled(address user, uint256 sharesSpent, uint256 assetsReceived);
    event NewShareAdded(address share);
    event FeeUpdated(address share, uint32 from, uint32 to);

    //============================== IMMUTABLES ===============================

    uint24 public immutable maxFeeForShare;

    constructor(uint24 _maxFeeForShare) Owned(msg.sender) {
        maxFeeForShare = _maxFeeForShare;
    }

    function addNewShare(ERC4626 share, uint24 fee) external onlyOwner {
        ShareSettings storage settings = shareSettings[share];
        if (address(settings.asset) != address(0)) revert WithdrawQueue__ShareAlreadyAdded();
        settings.asset = share.asset();
        settings.assetDecimals = settings.asset.decimals();
        settings.shareDecimals = share.decimals();
        settings.fee = fee;

        emit NewShareAdded(address(share));
    }

    function updateFee(ERC4626 share, uint24 fee) external onlyOwner {
        ShareSettings storage settings = shareSettings[share];
        if (address(settings.asset) == address(0)) revert WithdrawQueue__ShareNotAdded();
        if (fee > maxFeeForShare) revert WithdrawQueue__MaxFeeforShareExceeded();
        emit FeeUpdated(address(share), settings.fee, fee);

        settings.fee = fee;
    }

    // TODO can users set a fee.
    // Stores users data based off ERC20 share
    // TODO does this really need to be reentrancy protected?
    function updateWithdrawRequest(ERC4626 share, WithdrawRequest calldata userRequest) external nonReentrant {
        ShareSettings memory settings = shareSettings[share];
        if (address(settings.asset) == address(0)) revert WithdrawQueue__ShareNotAdded();

        // Validate amount.
        if (userRequest.sharesToWithdraw > share.balanceOf(msg.sender)) revert WithdrawQueue__BadAmount();
        // Validate deadline.
        if (block.timestamp > userRequest.deadline) revert WithdrawQueue__BadDeadline();
        // Validate approval.
        if (share.allowance(msg.sender, address(this)) < userRequest.sharesToWithdraw)
            revert WithdrawQueue__BadAllowance();
        // Validate fee is less than maxFee.
        if (userRequest.maximumFee < settings.fee) revert WithdrawQueue__BadMaximumFee();

        WithdrawRequest storage request = userWithdrawRequest[msg.sender][share];

        request.deadline = userRequest.deadline;
        request.maximumFee = userRequest.maximumFee;
        request.minimumSharePrice = userRequest.minimumSharePrice;
        request.sharesToWithdraw = userRequest.sharesToWithdraw;

        // Emit full amount user has.
        emit RequestUpdated(
            msg.sender,
            userRequest.sharesToWithdraw,
            userRequest.deadline,
            userRequest.minimumSharePrice
        );
    }

    // TODO maybe solver address should be input?
    function solve(ERC4626 share, address[] calldata users, bytes calldata runData) external nonReentrant {
        // Load settings.
        ShareSettings memory settings = shareSettings[share];
        {
            // Validate settings.
            // NOTE if shares conform to ERC4626 standard, these checks are not needed,
            // but additional gas overhead is minimal compared to solve, so better to revert
            // here if something doesn't line up, than to proceed with solve.
            ERC20 asset = share.asset();
            if (settings.asset != asset) revert WithdrawQueue__AssetChanged();
            if (settings.assetDecimals != asset.decimals()) revert WithdrawQueue__AssetDecimalsChanged();
            if (settings.shareDecimals != share.decimals()) revert WithdrawQueue__ShareDecimalsChanged();
        }

        // Determine the required amount of share.asset() solver must provide.
        uint256 minExecutionSharePrice = share.previewRedeem(10 ** settings.shareDecimals).mulDivDown(
            1e6 - settings.fee,
            1e6
        );

        uint256 sharesToSolver;
        for (uint256 i; i < users.length; ++i) {
            WithdrawRequest storage request = userWithdrawRequest[users[i]][share];

            if (request.inSolve) revert WithdrawQueue__UserRepeated();
            if (block.timestamp > request.deadline) revert WithdrawQueue__RequestDeadlineExceeded();
            if (settings.fee > request.maximumFee) revert WithdrawQueue__RequestMaximumFeeExceeded();
            if (minExecutionSharePrice < uint256(request.minimumSharePrice).changeDecimals(4, settings.assetDecimals))
                revert WithdrawQueue__RequestMinimumSharePriceNotMet();

            // If all checks above passed, the users request is valid and should be fulfilled.
            sharesToSolver += request.sharesToWithdraw;
            request.inSolve = true;
            // Transfer shares from user to solver.
            share.safeTransferFrom(users[i], msg.sender, request.sharesToWithdraw);
            continue;
        }

        uint256 requiredAssets = minExecutionSharePrice.mulDivDown(sharesToSolver, 10 ** settings.shareDecimals);

        ISolver(msg.sender).finishSolve(runData, sharesToSolver, requiredAssets);

        for (uint256 i; i < users.length; ++i) {
            WithdrawRequest storage request = userWithdrawRequest[users[i]][share];

            if (request.inSolve) {
                // We know that the minimum price and deadline arguments are satisfied since this can only be true if they were.

                // Send user their share of assets.
                uint256 assetsToUser = requiredAssets.mulDivDown(request.sharesToWithdraw, sharesToSolver);
                settings.asset.safeTransferFrom(msg.sender, users[i], assetsToUser);

                emit RequestFulfilled(users[i], request.sharesToWithdraw, assetsToUser);

                // Refund some gas to solver.
                // TODO this does not seem to be refunding any gas, and only costs money.
                delete userWithdrawRequest[users[i]][share];
            } else revert WithdrawQueue__UserNotInSolve();
        }
    }
}
