// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {AtomicQueue, ERC20, SafeTransferLib} from "./AtomicQueue.sol";
import {IAtomicSolver} from "./IAtomicSolver.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";
import {IWEETH} from "src/interfaces/external/IStaking.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

/**
 * @title AtomicSolverV2
 * @author crispymangoes
 */
contract AtomicSolverV2 is IAtomicSolver, Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    // ========================================= CONSTANTS =========================================

    address internal constant MAINNET_EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant MAINNET_WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant ARBITRUM_WEETH = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe;

    // ========================================= ENUMS =========================================

    /**
     * @notice The Solve Type, used in `finishSolve` to determine the logic used.
     * @notice P2P Solver wants to swap share.asset() for user(s) shares
     * @notice REDEEM Solver needs to redeem shares, then can cover user(s) required assets.
     */
    enum SolveType {
        P2P,
        REDEEM,
        REDEEM_LIQUID
    }

    //============================== ERRORS ===============================

    error AtomicSolverV2___WrongInitiator();
    error AtomicSolverV2___AlreadyInSolveContext();
    error AtomicSolverV2___FailedToSolve();
    error AtomicSolverV2___SolveMaxAssetsExceeded(uint256 actualAssets, uint256 maxAssets);
    error AtomicSolverV2___P2PSolveMinSharesNotMet(uint256 actualShares, uint256 minShares);
    error AtomicSolverV2___RedeemSolveMinAssetDeltaNotMet(uint256 actualDelta, uint256 minDelta);
    error AtomicSolverV2___UnsupportedRedeemPair(address asset, address want);
    error AtomicSolverV2___UnsupportedLiquidPair(address asset, address want);

    //============================== IMMUTABLES ===============================

    ERC20 public immutable eETH;
    ERC20 public immutable weETH;

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {
        address eEthAddress;
        address weEthAddress;

        if (block.chainid == 1) {
            eEthAddress = MAINNET_EETH;
            weEthAddress = MAINNET_WEETH;
        } else if (block.chainid == 42161) {
            weEthAddress = ARBITRUM_WEETH;
        }

        eETH = ERC20(eEthAddress);
        weETH = ERC20(weEthAddress);
    }

    //============================== SOLVE FUNCTIONS ===============================
    /**
     * @notice Solver wants to exchange p2p share.asset() for withdraw queue shares.
     * @dev Solver should approve this contract to spend share.asset().
     */
    function p2pSolve(
        AtomicQueue queue,
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        uint256 minOfferReceived,
        uint256 maxAssets
    ) external requiresAuth {
        bytes memory runData = abi.encode(SolveType.P2P, msg.sender, minOfferReceived, maxAssets);

        // Solve for `users`.
        queue.solve(offer, want, users, runData, address(this));
    }

    /**
     * @notice Solver wants to redeem withdraw offer shares, to help cover withdraw.
     * @dev `offer` MUST be an ERC4626 vault.
     * @dev `want` MUST equal the ERC4626 vault's asset.
     */
    function redeemSolve(
        AtomicQueue queue,
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        uint256 minAssetDelta,
        uint256 maxAssets
    ) external requiresAuth {
        bytes memory runData = abi.encode(SolveType.REDEEM, msg.sender, minAssetDelta, maxAssets);

        // Solve for `users`.
        queue.solve(offer, want, users, runData, address(this));
    }

    /**
     * @notice Solver wants to redeem withdraw offer shares, to help cover withdraw.
     * @dev `offer` MUST be an ERC4626 vault.
     * @dev `want` MUST equal the ERC4626 vault's asset or form an eETH/weETH pair with it.
     */
    function redeemLiquidSolve(
        AtomicQueue queue,
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        uint256 minAssetDelta,
        uint256 maxAssets
    ) external requiresAuth {
        bytes memory runData = abi.encode(SolveType.REDEEM_LIQUID, msg.sender, minAssetDelta, maxAssets);

        // Solve for `users`.
        queue.solve(offer, want, users, runData, address(this));
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
        ERC20 offer,
        ERC20 want,
        uint256 offerReceived,
        uint256 wantApprovalAmount
    ) external requiresAuth {
        if (initiator != address(this)) revert AtomicSolverV2___WrongInitiator();

        address queue = msg.sender;

        SolveType _type = abi.decode(runData, (SolveType));

        if (_type == SolveType.P2P) {
            _p2pSolve(queue, runData, offer, want, offerReceived, wantApprovalAmount);
        } else if (_type == SolveType.REDEEM) {
            _redeemSolve(queue, runData, offer, want, offerReceived, wantApprovalAmount);
        } else if (_type == SolveType.REDEEM_LIQUID) {
            _redeemLiquidSolve(queue, runData, offer, want, offerReceived, wantApprovalAmount);
        }
    }

    //============================== HELPER FUNCTIONS ===============================

    /**
     * @notice Helper function containing the logic to handle p2p solves.
     */
    function _p2pSolve(
        address queue,
        bytes memory runData,
        ERC20 offer,
        ERC20 want,
        uint256 offerReceived,
        uint256 wantApprovalAmount
    ) internal {
        (, address solver, uint256 minOfferReceived, uint256 maxAssets) =
            abi.decode(runData, (SolveType, address, uint256, uint256));

        // Make sure solver is receiving the minimum amount of offer.
        if (offerReceived < minOfferReceived) {
            revert AtomicSolverV2___P2PSolveMinSharesNotMet(offerReceived, minOfferReceived);
        }

        // Make sure solvers `maxAssets` was not exceeded.
        if (wantApprovalAmount > maxAssets) {
            revert AtomicSolverV2___SolveMaxAssetsExceeded(wantApprovalAmount, maxAssets);
        }

        // Transfer required want from solver.
        want.safeTransferFrom(solver, address(this), wantApprovalAmount);

        // Transfer offer to solver.
        offer.safeTransfer(solver, offerReceived);

        // Approve queue to spend wantApprovalAmount.
        want.safeApprove(queue, wantApprovalAmount);
    }

    /**
     * @notice Helper function containing the logic to handle redeem solves.
     */
    function _redeemSolve(
        address queue,
        bytes memory runData,
        ERC20 offer,
        ERC20 want,
        uint256 offerReceived,
        uint256 wantApprovalAmount
    ) internal {
        (, address solver, uint256 minAssetDelta, uint256 maxAssets) =
            abi.decode(runData, (SolveType, address, uint256, uint256));

        // Make sure solvers `maxAssets` was not exceeded.
        if (wantApprovalAmount > maxAssets) {
            revert AtomicSolverV2___SolveMaxAssetsExceeded(wantApprovalAmount, maxAssets);
        }

        // Redeem the shares, sending assets to solver.
        ERC4626 share = ERC4626(address(offer));
        ERC20 asset = share.asset();
        if (address(want) != address(asset)) {
            revert AtomicSolverV2___UnsupportedRedeemPair(address(asset), address(want));
        }
        uint256 assetsFromRedeem = share.redeem(offerReceived, solver, address(this));

        _enforceMinAssetDelta(assetsFromRedeem, wantApprovalAmount, minAssetDelta);

        // Transfer required assets from solver.
        want.safeTransferFrom(solver, address(this), wantApprovalAmount);

        // Approve queue to spend wantApprovalAmount.
        want.safeApprove(queue, wantApprovalAmount);
    }

    /**
     * @notice Helper function containing the logic to handle redeem solves.
     */
    function _redeemLiquidSolve(
        address queue,
        bytes memory runData,
        ERC20 offer,
        ERC20 want,
        uint256 offerReceived,
        uint256 wantApprovalAmount
    ) internal {
        (, address solver, uint256 minAssetDelta, uint256 maxAssets) =
            abi.decode(runData, (SolveType, address, uint256, uint256));

        // Make sure solvers `maxAssets` was not exceeded.
        if (wantApprovalAmount > maxAssets) {
            revert AtomicSolverV2___SolveMaxAssetsExceeded(wantApprovalAmount, maxAssets);
        }

        // Redeem the shares, sending assets to solver.
        ERC4626 share = ERC4626(address(offer));
        uint256 assetsFromRedeem = share.redeem(offerReceived, solver, address(this));

        uint256 wantAmountInAsset = _wantAmountInAsset(want, share.asset(), wantApprovalAmount);
        _enforceMinAssetDelta(assetsFromRedeem, wantAmountInAsset, minAssetDelta);

        // Transfer required assets from solver.
        if (want.balanceOf(solver) < wantApprovalAmount) {
            // Check if want is eETH, if so see if there is enough weETH to unwrap and cover withdraw.
            if (address(want) == address(eETH)) {
                uint256 unwrapAmount = _wantAmountInAsset(want, weETH, wantApprovalAmount);
                if (unwrapAmount <= weETH.balanceOf(solver)) {
                    weETH.safeTransferFrom(solver, address(this), unwrapAmount);
                    uint256 amountOut = IWEETH(address(weETH)).unwrap(unwrapAmount);
                    if (amountOut < wantApprovalAmount) revert AtomicSolverV2___FailedToSolve();
                } else {
                    revert AtomicSolverV2___FailedToSolve();
                }
            }
            // else check if want is weETH, if so see if there is enough eETH to wrap and cover withdraw.
            else if (address(want) == address(weETH)) {
                uint256 wrapAmount = _wantAmountInAsset(want, eETH, wantApprovalAmount);
                if (wrapAmount <= eETH.balanceOf(solver)) {
                    eETH.safeTransferFrom(solver, address(this), wrapAmount);
                    eETH.safeApprove(address(weETH), wrapAmount);
                    uint256 amountOut = IWEETH(address(weETH)).wrap(wrapAmount);
                    if (amountOut < wantApprovalAmount) revert AtomicSolverV2___FailedToSolve();
                } else {
                    revert AtomicSolverV2___FailedToSolve();
                }
            } else {
                revert AtomicSolverV2___FailedToSolve();
            }
        } else {
            want.safeTransferFrom(solver, address(this), wantApprovalAmount);
        }

        // Approve queue to spend wantApprovalAmount.
        want.safeApprove(queue, wantApprovalAmount);
    }

    function _enforceMinAssetDelta(uint256 assetsFromRedeem, uint256 assetsRequired, uint256 minAssetDelta)
        internal
        pure
    {
        if (assetsFromRedeem < assetsRequired) {
            revert AtomicSolverV2___RedeemSolveMinAssetDeltaNotMet(0, minAssetDelta);
        }

        uint256 assetDelta = assetsFromRedeem - assetsRequired;
        if (assetDelta < minAssetDelta) {
            revert AtomicSolverV2___RedeemSolveMinAssetDeltaNotMet(assetDelta, minAssetDelta);
        }
    }

    function _wantAmountInAsset(ERC20 want, ERC20 asset, uint256 wantAmount)
        internal
        view
        returns (uint256 assetAmount)
    {
        if (address(want) == address(asset)) return wantAmount;

        if (address(want) == address(weETH) && address(asset) == address(eETH)) {
            uint256 rate = IWEETH(address(weETH)).getRate();
            // getRate() rounds the exact eETH-per-weETH ratio down. Increasing the rate by one
            // gives a strict upper bound on the exact ratio before rounding the required amount up.
            return wantAmount.mulDivUp(rate + 1, 1e18);
        }
        if (address(want) == address(eETH) && address(asset) == address(weETH)) {
            uint256 rate = IWEETH(address(weETH)).getRate();
            return wantAmount.mulDivUp(1e18, rate);
        }

        revert AtomicSolverV2___UnsupportedLiquidPair(address(asset), address(want));
    }
}
