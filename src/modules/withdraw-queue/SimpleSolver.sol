// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { WithdrawQueue, ERC4626, ERC20, SafeTransferLib } from "./WithdrawQueue.sol";
import { ISolver } from "./ISolver.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";

/**
 * @title SimpleSolver
 * @notice Allows 3rd party solvers to use an audited Solver contract for simple soles..
 * @author crispymangoes
 */
contract SimpleSolver is ISolver, ReentrancyGuard {
    using SafeTransferLib for ERC4626;
    using SafeTransferLib for ERC20;

    // ========================================= ENUMS =========================================

    /**
     * @notice The Solve Type, used in `finishSolve` to determine the logic used.
     * @notice P2P Solver wants to swap share.asset() for user(s) shares
     * @notice REDEEM Solver needs to redeem shares, then can cover user(s) required assets.
     */
    enum SolveType {
        P2P,
        REDEEM
    }

    //============================== ERRORS ===============================

    error SimpleSolver___WrongInitiator();
    error SimpleSolver___AlreadyInSolveContext();
    error SimpleSolver___OnlyQueue();
    error SimpleSolver___SolveMaxAssetsExceeded(uint256 actualAssets, uint256 maxAssets);
    error SimpleSolver___P2PSolveMinSharesNotMet(uint256 actualShares, uint256 minShares);
    error SimpleSolver___RedeemSolveMinAssetDeltaNotMet(uint256 actualDelta, uint256 minDelta);

    //============================== IMMUTABLES ===============================

    /**
     * @notice The withdraw queue this simple solver works with.
     */
    WithdrawQueue public immutable queue;

    constructor(address _queue) {
        queue = WithdrawQueue(_queue);
    }

    //============================== SOLVE FUNCTIONS ===============================
    /**
     * @notice Solver wants to exchange p2p share.asset() for withdraw queue shares.
     * @dev Solver should approve this contract to spend share.asset().
     */
    function p2pSolve(
        ERC4626 share,
        address[] calldata users,
        uint256 minSharesReceived,
        uint256 maxAssets
    ) external nonReentrant {
        bytes memory runData = abi.encode(SolveType.P2P, msg.sender, share, minSharesReceived, maxAssets);

        // Solve for `users`.
        queue.solve(share, users, runData, address(this));
    }

    /**
     * @notice Solver wants to redeem withdraw queue shares, to help cover withdraw.
     * @dev Solver should approve this contract to spend share.asset().
     * @dev This solve will redeem assets to the solver, to handle cases where redeem returns more than
     *      share.asset(). In these cases the solver should know, and have enough share.asset() to cover shortfall.
     * @dev It is extremely likely that this TX will be MEVed, private mem pools should be used to send it.
     */
    function redeemSolve(
        ERC4626 share,
        address[] calldata users,
        uint256 minAssetDelta,
        uint256 maxAssets
    ) external nonReentrant {
        bytes memory runData = abi.encode(SolveType.REDEEM, msg.sender, share, minAssetDelta, maxAssets);

        // Solve for `users`.
        queue.solve(share, users, runData, address(this));
    }

    //============================== ISOLVER FUNCTIONS ===============================

    /**
     * @notice Implement the finishSolve function WithdrawQueue expects to call.
     * @dev nonReentrant is not needed on this function because it is impossible to reenter,
     *      because the above solve functions have the nonReentrant modifier.
     *      The only way to have the first 2 checks pass is if the msg.sender is the queue,
     *      and this contract is msg.sender of `Queue.solve()`, which is only called in the above
     *      functions.
     */
    function finishSolve(
        bytes calldata runData,
        address initiator,
        uint256 sharesReceived,
        uint256 assetApprovalAmount
    ) external {
        if (msg.sender != address(queue)) revert SimpleSolver___OnlyQueue();
        if (initiator != address(this)) revert SimpleSolver___WrongInitiator();

        SolveType _type = abi.decode(runData, (SolveType));

        if (_type == SolveType.P2P) _p2pSolve(runData, sharesReceived, assetApprovalAmount);
        else if (_type == SolveType.REDEEM) _redeemSolve(runData, sharesReceived, assetApprovalAmount);
    }

    //============================== HELPER FUNCTIONS ===============================

    /**
     * @notice Helper function containing the logic to handle p2p solves.
     */
    function _p2pSolve(bytes memory runData, uint256 sharesReceived, uint256 assetApprovalAmount) internal {
        (, address solver, ERC4626 share, uint256 minSharesReceived, uint256 maxAssets) = abi.decode(
            runData,
            (SolveType, address, ERC4626, uint256, uint256)
        );

        // Make sure solver is receiving the minimum amount of shares.
        if (sharesReceived < minSharesReceived)
            revert SimpleSolver___P2PSolveMinSharesNotMet(sharesReceived, minSharesReceived);

        // Make sure solvers `maxAssets` was not exceeded.
        if (assetApprovalAmount > maxAssets)
            revert SimpleSolver___SolveMaxAssetsExceeded(assetApprovalAmount, maxAssets);

        ERC20 asset = share.asset();

        // Transfer required assets from solver.
        asset.safeTransferFrom(solver, address(this), assetApprovalAmount);

        // Transfer shares to solver.
        share.safeTransfer(solver, sharesReceived);

        // Approve queue to spend assetApprovalAmount.
        asset.safeApprove(address(queue), assetApprovalAmount);
    }

    /**
     * @notice Helper function containing the logic to handle redeem solves.
     */
    function _redeemSolve(bytes memory runData, uint256 sharesReceived, uint256 assetApprovalAmount) internal {
        (, address solver, ERC4626 share, uint256 minAssetDelta, uint256 maxAssets) = abi.decode(
            runData,
            (SolveType, address, ERC4626, uint256, uint256)
        );

        // Make sure solvers `maxAssets` was not exceeded.
        if (assetApprovalAmount > maxAssets)
            revert SimpleSolver___SolveMaxAssetsExceeded(assetApprovalAmount, maxAssets);

        // Redeem the shares, sending assets to solver.
        uint256 assetsFromRedeem = share.redeem(sharesReceived, solver, address(this));

        uint256 assetDelta = assetsFromRedeem - assetApprovalAmount;
        if (assetDelta < minAssetDelta) revert SimpleSolver___RedeemSolveMinAssetDeltaNotMet(assetDelta, minAssetDelta);

        ERC20 asset = share.asset();

        // Transfer required assets from solver.
        asset.safeTransferFrom(solver, address(this), assetApprovalAmount);

        // Approve queue to spend assetApprovalAmount.
        asset.safeApprove(address(queue), assetApprovalAmount);
    }
}
