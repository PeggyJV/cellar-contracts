// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeERC20, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IBooster } from "src/interfaces/external/IBooster.sol";

import { IRewardPool } from "src/interfaces/external/IRewardPool.sol";
import { ICurvePool } from "src/interfaces/external/ICurvePool.sol";


/**
 * @title Convex Adaptor
 * @notice Allows Cellars to interact with Convex Positions.
 * @author 
 */
contract ConvexAdaptor is BaseAdaptor {
    using SafeERC20 for ERC20;
    using Math for uint256;
    using SafeCast for uint256;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(uint256 pid, ERC20 lpToken, ICurvePool pool)
    // Where:
    // - pid is the pool id of the convex pool
    // - lpToken is the lp token concerned by the pool
    // - ICurvePool is the curve pool where the lp token was minted
    //====================================================================

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

    /**
     * @notice The Booster contract on Ethereum Mainnet where all deposits happen in Convex
     */
    function booster() internal pure returns (IBooster) {
        return IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    }

    /**
     @notice Attempted to deposit into convex but failed
     */
    error ConvexAdaptor_DepositFailed();

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice User withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Calculates this positions LP tokens underlying worth in terms of `token0`.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (uint256 pid, ERC20 lpToken, ICurvePool pool) = abi.decode(adaptorData, (uint256, ERC20, ICurvePool));

        (,,,address rewardPool,,) = (booster()).poolInfo(pid);

        uint256 stakedBalance = IRewardPool(rewardPool).balanceOf(msg.sender);

        if(stakedBalance == 0) return 0;

        // returns how much do we get if were to withdraw the whole position from convex and curve
        return pool.calc_withdraw_one_coin(stakedBalance, 0);
    }

    /**
     * @notice Returns `coins(0)`
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        (, , ICurvePool pool) = abi.decode(adaptorData, (uint256, ERC20, ICurvePool));
        return ERC20(pool.coins(0));
    }

    //============================================ Strategist Functions ===========================================

/**
     * @notice Open a position in convex
     */
    function openPosition(
        uint256 amount,
        uint256 pid,
        ERC20 lpToken
    ) public {
        lpToken.safeApprove(address(booster()), amount);

        // always assume we are staking
        if(!(booster()).deposit(pid, amount, true)) {
            revert ConvexAdaptor_DepositFailed();
        }
    }

    /**
     * @notice Close position in convex
     */
    function takeFromPosition(
        uint256 pid,
        uint256 amount
    ) public {
        (booster()).withdrawTo(pid, amount, msg.sender);    
    }

    /**
     * @notice Close position in convex
     */
    function closePosition(
        uint256 pid,
        uint256 amount
    ) public {
        (booster()).withdrawAll(pid, amount, msg.sender);  
    }


    // function claim(bytes memory adaptorData) public pure returns (uint256) {
    //     // TODO
    //     return 0;
    // }


}
