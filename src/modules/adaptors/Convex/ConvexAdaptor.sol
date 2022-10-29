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
    // adaptorData = abi.encode(uint256 pid, ERC20 lpToken)
    // Where:
    // - pid is the pool id of the convex pool
    // - lpToken is the lp token concerned by the pool
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
     * @notice The Booster contract on Ethereum Mainnet.
     */
    function booster() internal pure returns (IBooster) {
        return IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    }

    /**
     * @notice The Curve 3pool contract on Ethereum Mainnet.
     */
    function curvePool() internal pure returns (ICurvePool) {
        return ICurvePool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
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
        uint256 amount,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        (uint256 pid, ERC20 lpToken) = abi.decode(adaptorData, (uint256, ERC20));

        lpToken.safeApprove(address(booster()), amount);

        // always assume we are staking
        if(!(booster()).deposit(pid, amount, true)) {
            revert ConvexAdaptor_DepositFailed();
        }
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(
        uint256 amount,
        address receiver,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        (uint256 pid, ) = abi.decode(adaptorData, (uint256, ERC20));

        // withdraw from this address to the receiver in parameter
        (booster()).withdrawTo(pid, amount, receiver);    
    }

    /**
     * @notice User withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        // TODO
        return 0;
    }

    /**
     * @notice Calculates this positions LP tokens underlying worth in terms of `token0`.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // TODO
        (, ERC20 lpToken) = abi.decode(adaptorData, (uint256, ERC20));
        return lpToken.balanceOf(address(this));
    }

    /**
     * @notice Returns `coins(0)`
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        (, ERC20 lpToken) = abi.decode(adaptorData, (uint256, ERC20));
        return ERC20((curvePool()).coins(0));
    }

    //============================================ Strategist Functions ===========================================

    // function claim(bytes memory adaptorData) public pure returns (uint256) {
    //     // TODO
    //     return 0;
    // }


    //============================================ Helper Functions ============================================
    /**
     * @notice Calculates the square root of the input.
     */
    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }
}
