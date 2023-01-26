// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBooster } from "src/interfaces/external/IBooster.sol";
import { IBaseRewardPool } from "src/interfaces/external/IBaseRewardPool.sol";

/**
 * @title Curve Adaptor
 * @notice Allows Cellars to interact with Curve liquidity pools.
 * @author crispymangoes
 */
//  TODO may not need the pid unless we want to support cellars using this as a holding position.
contract CurveAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ERC20 lpToken, IBaseRewardPool rewarder, uint256 poolId)
    // Where:
    // `lpToken` is the Curve LP token this adaptor is working with
    // `poolId` is the Convex booster pool id this adaptor is working with
    // `rewarder` is the rewarder contract this adaptor works with
    //================= Configuration Data Specification =================
    // NOT USED
    //================================ NOTES ==============================
    // This adaptor is not intended to be used as a position. Rather it is only to be used by strategists so
    // they can interact with Curve and enter/exit LP positions.
    //=====================================================================

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Convex Adaptor V 0.0"));
    }

    function booster() public pure returns (IBooster) {
        return IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar already has possession of users ERC20 assets by the time this function is called,
     *         so there is nothing to do.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice Cellar just needs to transfer ERC20 token to `receiver`.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @dev configurationData is NOT used
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        _externalReceiverCheck(receiver);

        (ERC20 lpToken, IBaseRewardPool rewarder) = abi.decode(adaptorData, (ERC20, IBaseRewardPool));

        // Withdraw assets, but do NOT harvest rewards.
        rewarder.withdrawAndUnwrap(assets, false);

        // Send assets to receiver.
        lpToken.safeTransfer(receiver, assets);
    }

    /**
     * @notice Identical to `balanceOf`, if an asset is used with a non ERC20 standard locking logic,
     *         then a NEW adaptor contract is needed.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        (, IBaseRewardPool rewarder) = abi.decode(adaptorData, (ERC20, IBaseRewardPool));
        return rewarder.balanceOf(msg.sender);
    }

    /**
     * @notice Returns the balance of `token`.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (, IBaseRewardPool rewarder) = abi.decode(adaptorData, (ERC20, IBaseRewardPool));
        return rewarder.balanceOf(msg.sender);
    }

    /**
     * @notice Returns `token`
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 lpToken = abi.decode(adaptorData, (ERC20));
        return lpToken;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    // TODO add functions for bposter deposit, rewarder withdraw, rewarder getReward
    function depositToConvex() public {}

    function withdrawFromConvex() public {}

    function harvest() public {}
}
