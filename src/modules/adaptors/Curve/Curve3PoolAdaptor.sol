// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeERC20, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IBooster } from "src/interfaces/external/IBooster.sol";
import { ICurvePool } from "src/interfaces/external/ICurvePool.sol";


/**
 * @title Curve 3 Pool Adaptor
 * @notice Allows Cellars to interact with Curve Positions.
 * @author 
 */
contract Curve3PoolAdaptor is BaseAdaptor {
    using SafeERC20 for ERC20;
    using Math for uint256;
    using SafeCast for uint256;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ICurvePool curvePool, address lpToken)
    // Where:
    // - curvePool is the pool concerned by the position
    // - lpToken is the lp generated by the pool (in old curve contracts, 
    //           it is not available as a public method in the pool)
    //====================================================================

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Curve 3Pool Adaptor V 0.0"));
    }

    /**
     @notice Attempted to deposit into Curve but failed
     */
    error CurveAdaptor_DepositFailed();

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
        (ICurvePool pool, ) = abi.decode(adaptorData, (ICurvePool, ERC20));
        return ERC20(pool.coins(0));
    }

    //============================================ Strategist Functions ===========================================

    function claim(bytes memory adaptorData) public pure returns (uint256) {
        
        return 0;
    }

    /**
     * @notice Allows strategist to open up arbritray Curve positions.
     */
    function openPosition(
        uint256[3] memory amounts, 
        uint256 minimumMintAmount, 
        ICurvePool pool
    ) public returns (uint256) {
        return pool.add_liquidity(amounts, minimumMintAmount);
    }

    function closePosition(
        bytes memory adaptorData,
        uint256 amount,
        uint256[3] memory minimumAmounts
    ) public returns (uint256[3] memory) {
        (ICurvePool pool, ) = abi.decode(adaptorData, (ICurvePool, address));
        return pool.remove_liquidity(amount, minimumAmounts);
    }

    function takeFromPosition(bytes memory adaptorData) public pure returns (uint256) {
        // TODO
        return 0;
    }

    function addToPosition(bytes memory adaptorData) public pure returns (uint256) {
        // TODO
        return 0;
    }

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
