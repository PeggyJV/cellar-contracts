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
    // 
    // Uses token0. In the case of curve3Pool it is DAI.
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
     * @notice Curve pools provide a calculation where the amount returned considers the swapping of token1 and token2
     * for token0 considering fees.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (ICurvePool pool, ERC20 lpToken) = abi.decode(adaptorData, (ICurvePool, ERC20));

        // Calculates amount of token0 is recieved when burning all LP tokens.
        uint256 lpBalance = lpToken.balanceOf(msg.sender);

        // return 0 if lp balance is null
        if(lpBalance == 0) return 0;

        return pool.calc_withdraw_one_coin(lpBalance, 0);
    }

    /**
     * @notice Returns `coins(0)` or token0
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        (ICurvePool pool, ) = abi.decode(adaptorData, (ICurvePool, ERC20));
        return ERC20(pool.coins(0));
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategist to open up arbritray Curve positions.
     * @notice Allows to send any combination of token0, token1 and token2 which the pool will
     * balance on deposit.
     * @notice If minted lp tokens is less than minimumMintAmount function will revert.
     * @param amounts token0, token1, and token2 amounts to be deposited.
     * @param minimumMintAmount minting at least this amount of lp tokens.
     * @param pool specifies the interface of the pool
     */
    function openPosition(
        uint256[3] memory amounts, 
        uint256 minimumMintAmount, 
        ICurvePool pool
    ) public {
        for(uint256 i; i<amounts.length; ) {
            if (amounts[i] != 0) {
                ERC20 token = ERC20(pool.coins(i));
                token.safeApprove(address(pool), amounts[i]);
            }
            // overflow is unrealistic
            unchecked {
                ++i;
            }
        }

        pool.add_liquidity(amounts, minimumMintAmount);
    }
    
    /**
     * @notice Strategist attempted to remove all of a positions liquidity using `takeFromPosition`,
     *         but they need to use `closePosition`.
     * @notice If receiving amount of token0 is less than minimumMintAmount function will revert.
     * @param amount lp token amount to be burned.
     * @param minimumMintAmount receiving at least this amount of token0.
     * @param pool specifies the interface of the pool
     * @param lpToken specifies the interface of the lp token
     */
    error Curve3PoolAdaptor__CallClosePosition();

    function takeFromPosition(
        uint256 amount,
        uint256 minimumAmount,
        ICurvePool pool,
        ERC20 lpToken
    ) public {
        // we should not be closing a position here
        if(lpToken.balanceOf(msg.sender) == amount) revert Curve3PoolAdaptor__CallClosePosition();
        _takeFromPosition(amount, minimumAmount, pool);
    }

    /**
     * @notice Executes the removal of liquidity in one coin: token0.
     * @notice If receiving amount of token0 is less than minimumMintAmount function will revert.
     * @param amount lp token amount to be burned.
     * @param minimumMintAmount receiving at least this amount of token0.
     * @param pool specifies the interface of the pool
     */
    function _takeFromPosition(
        uint256 amount,
        uint256 minimumAmount,
        ICurvePool pool
    ) internal {
        pool.remove_liquidity_one_coin(amount, 0, minimumAmount);
    }

    /**
     * @notice Strategist use `closePosition` to remove all of a positions liquidity.
     * @notice If receiving amount of token0 is less than minimumMintAmount function will revert.
     * @param minimumMintAmount receiving at least this amount of token0.
     * @param pool specifies the interface of the pool
     * @param lpToken specifies the interface of the lp token
     */
    error Curve3PoolAdaptor__PositionClosed();

    function closePosition(
        uint256 minimumAmount,
        ICurvePool pool,
        ERC20 lpToken
    ) public {
        uint256 amountToWithdraw = lpToken.balanceOf(address(this));

        if(amountToWithdraw == 0) revert Curve3PoolAdaptor__PositionClosed();
        _takeFromPosition(amountToWithdraw, minimumAmount, pool);
    }

    /**
     * @notice Allows strategist to add liquidity to a Curve position.
     * @notice Allows to send any combination of token0, token1 and token2 which the pool will
     * balance on deposit.
     * @notice If minted lp tokens is less than minimumMintAmount function will revert.
     * @param amounts token0, token1, and token2 amounts to be deposited.
     * @param minimumMintAmount minting at least this amount of lp tokens.
     * @param pool specifies the interface of the pool
     */
    function addToPosition(        
        uint256[3] memory amounts, 
        uint256 minimumMintAmount, 
        ICurvePool pool
    ) public {

        for(uint256 i; i<amounts.length; ) {
            if (amounts[i] != 0) {
                ERC20 token = ERC20(pool.coins(i));
                token.safeApprove(address(pool), amounts[i]);
            }

            // overflow is unrealistic
            unchecked {
                ++i;
            }
        }

        pool.add_liquidity(amounts, minimumMintAmount);
    }

}
