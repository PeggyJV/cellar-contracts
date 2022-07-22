// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { IPool } from "src/interfaces/IPool.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC4626, ERC20 } from "src/base/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { IMasterChef } from "src/interfaces/IMasterChef.sol";
import { IAaveToken } from "src/interfaces/IAaveToken.sol";
import { Registry } from "src/Registry.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { DataTypes } from "src/interfaces/DataTypes.sol";

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

contract AaveATokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    /*
        adaptorData = abi.encode(aToken address)
    */

    //============================================ Implement Base Functions ===========================================
    function deposit(uint256 assets, bytes memory adaptorData) public override {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        _depositToAave(ERC20(token.UNDERLYING_ASSET_ADDRESS()), assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData
    ) public override {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        _withdrawFromAave(ERC20(token.UNDERLYING_ASSET_ADDRESS()), assets);
        ERC20(token.UNDERLYING_ASSET_ADDRESS()).safeTransfer(receiver, assets);
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address token = abi.decode(adaptorData, (address));
        return ERC20(token).balanceOf(msg.sender);
    }

    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        return ERC20(token.UNDERLYING_ASSET_ADDRESS());
    }

    //============================================ Override Hooks ===========================================
    function afterHook(bytes memory hookData) public view virtual override returns (bool) {
        //TODO hookDat would contain a minimum healthFactor or something
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        (, , , , , uint256 healthFactor) = pool.getUserAccountData(msg.sender);

        uint256 minHealthFactor = abi.decode(hookData, (uint256));

        return healthFactor >= minHealthFactor;
    }

    //============================================ High Level Callable Functions ============================================
    function depositToAave(bytes memory callData) public {
        (ERC20 tokenToDeposit, uint256 amountToDeposit) = abi.decode(callData, (ERC20, uint256));
        amountToDeposit = _maxAvailable(tokenToDeposit, amountToDeposit);
        _depositToAave(tokenToDeposit, amountToDeposit);
        //require(Cellar(address(this)).isPositionUsed()
    }

    function withdrawFromAave(bytes memory callData) public {
        (ERC20 tokenToWithdraw, uint256 amountToWithdraw) = abi.decode(callData, (ERC20, uint256));
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        //DataTypes.ReserveData memory types = pool.getReserveData(address(tokenToWithdraw));
        //address aToken = types.aTokenAddress;
        //amountToWithdraw = _maxAvailable(ERC20(aToken), amountToWithdraw);
        _withdrawFromAave(tokenToWithdraw, amountToWithdraw);
    }

    //============================================ AAVE Logic ============================================
    //TODO might need to add a check that toggles use reserve as collateral
    function _depositToAave(ERC20 tokenToDeposit, uint256 amountToDeposit) internal {
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        tokenToDeposit.safeApprove(address(pool), amountToDeposit);
        pool.deposit(address(tokenToDeposit), amountToDeposit, address(this), 0);
    }

    function _borrowFromAave(ERC20 tokenToBorrow, uint256 amountToBorrow) internal {
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        pool.borrow(address(tokenToBorrow), amountToBorrow, 2, 0, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
    }

    function _repayAaveDebt(ERC20 tokenToRepay, uint256 amountToRepay) internal {
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        tokenToRepay.safeApprove(address(pool), amountToRepay);
        pool.repay(address(tokenToRepay), amountToRepay, 2, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
    }

    function _withdrawFromAave(ERC20 tokenToWithdraw, uint256 amountToWithdraw) internal {
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        pool.withdraw(address(tokenToWithdraw), amountToWithdraw, address(this));
    }
}
