// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { WithdrawQueue, ERC4626, ERC20, SafeTransferLib } from "./WithdrawQueue.sol";
import { ISolver } from "./ISolver.sol";

/**
 * @title SimpleSolver
 * @notice Allows 3rd party solvers to use an audited Solver contract for simple soles..
 * @author crispymangoes
 */
contract SimpleSolver is ISolver {
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

    // ========================================= CONSTANTS =========================================

    /**
     * @notice The dead address to set activeSolver to when not in use.
     */
    address private DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice Address that is currently performing a solve.
     * @dev Important so that users who give approval to this contract, can not have
     *      their funds spent unless they are the ones actively solving.
     */
    address private activeSolver;

    //============================== ERRORS ===============================

    error SimpleSolver___NotInSolveContextOrNotActiveSolver();
    error SimpleSolver___SolveMaxAssetsExceeded(uint256 actualAssets, uint256 maxAssets);
    error SimpleSolver___P2PSolveMinSharesNotMet(uint256 actualShares, uint256 minShares);
    error SimpleSolver___RedeemSolveMinAssetDeltaNotMet(uint256 actualDelta, uint256 minDelta);

    //============================== IMMUTABLES ===============================

    constructor() {
        activeSolver = DEAD_ADDRESS;
    }

    //============================== SOLVE FUNCTIONS ===============================
    /**
     * @notice Solver wants to exchange p2p share.asset() for withdraw queue shares.
     * @dev Solver should approve this contract to spend share.asset().
     */
    function p2pSolve(
        WithdrawQueue queue,
        ERC4626 share,
        address[] calldata users,
        uint256 minSharesReceived,
        uint256 maxAssets
    ) external {
        bytes memory runData = abi.encode(SolveType.P2P, msg.sender, queue, share, minSharesReceived, maxAssets);

        // Solve for `users`.
        activeSolver = msg.sender;
        queue.solve(share, users, runData, address(this));
        activeSolver = address(DEAD_ADDRESS);
    }

    /**
     * @notice Solver wants to redeem withdraw queue shares, to help cover withdraw.
     * @dev Solver should approve this contract to spend share.asset().
     * @dev This solve will redeem assets to the solver, to handle cases where redeem returns more than
     *      share.asset(). In these cases the solver should know, and have enough share.asset() to cover shortfall.
     * @dev It is extreemely likely that this TX will be MEVed, private mem pools should be used to send it.
     */
    function redeemSolve(
        WithdrawQueue queue,
        ERC4626 share,
        address[] calldata users,
        uint256 minAssetDelta,
        uint256 maxAssets
    ) external {
        bytes memory runData = abi.encode(SolveType.REDEEM, msg.sender, queue, share, minAssetDelta, maxAssets);

        // Solve for `users`.
        activeSolver = msg.sender;
        queue.solve(share, users, runData, address(this));
        activeSolver = address(DEAD_ADDRESS);
    }

    //============================== ISOLVER FUNCTIONS ===============================

    /**
     * @notice Implement the finishSolve function WithdrawQueue expects to call.
     */
    function finishSolve(bytes calldata runData, uint256 sharesReceived, uint256 assetApprovalAmount) external {
        (SolveType _type, address solver) = abi.decode(runData, (SolveType, address));

        address _activeSolver = activeSolver;
        if (_activeSolver == DEAD_ADDRESS || solver != _activeSolver)
            revert SimpleSolver___NotInSolveContextOrNotActiveSolver();

        if (_type == SolveType.P2P) _p2pSolve(runData, sharesReceived, assetApprovalAmount);
        else if (_type == SolveType.REDEEM) _redeemSolve(runData, sharesReceived, assetApprovalAmount);
    }

    //============================== HELPER FUNCTIONS ===============================

    function _p2pSolve(bytes memory runData, uint256 sharesReceived, uint256 assetApprovalAmount) internal {
        (, address solver, address queue, ERC4626 share, uint256 minSharesReceived, uint256 maxAssets) = abi.decode(
            runData,
            (SolveType, address, address, ERC4626, uint256, uint256)
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
        asset.safeApprove(queue, assetApprovalAmount);
    }

    function _redeemSolve(bytes memory runData, uint256 sharesReceived, uint256 assetApprovalAmount) internal {
        (, address solver, address queue, ERC4626 share, uint256 minAssetDelta, uint256 maxAssets) = abi.decode(
            runData,
            (SolveType, address, address, ERC4626, uint256, uint256)
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
        asset.safeApprove(queue, assetApprovalAmount);
    }
}
