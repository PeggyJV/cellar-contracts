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

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

contract AaveDebtTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    /*
        adaptorData = abi.encode( debt token address)
    */

    //============================================ Global Functions ===========================================
    function pool() internal pure returns (IPool) {
        return IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    }

    //============================================ Implement Base Functions ===========================================
    function deposit(uint256 assets, bytes memory adaptorData) public override {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        _repayAaveDebt(ERC20(token.UNDERLYING_ASSET_ADDRESS()), assets);
    }

    //TODO currently does not check LTV when trying to borrow
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData
    ) public override {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        _borrowFromAave(ERC20(token.UNDERLYING_ASSET_ADDRESS()), assets);
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
        //TODO hookData would contain a minimum healthFactor or something
        (, , , , , uint256 healthFactor) = pool().getUserAccountData(msg.sender);

        uint256 minHealthFactor = abi.decode(hookData, (uint256));

        return healthFactor >= minHealthFactor;
    }

    //============================================ High Level Callable Functions ============================================
    function borrowFromAave(bytes memory callData) public {
        (ERC20 tokenToBorrow, uint256 amountToBorrow) = abi.decode(callData, (ERC20, uint256));
        _borrowFromAave(tokenToBorrow, amountToBorrow);
    }

    function repayAaveDebt(bytes memory callData) public {
        (ERC20 tokenToRepay, uint256 amountToRepay) = abi.decode(callData, (ERC20, uint256));
        amountToRepay = _maxAvailable(tokenToRepay, amountToRepay);
        _repayAaveDebt(tokenToRepay, amountToRepay);
    }

    function simpleFlashLoan(bytes memory callData) public {
        (ERC20 flashLoanToken, uint256 loanAmount, bytes memory params) = abi.decode(callData, (ERC20, uint256, bytes));
        _simpleFlashLoan(flashLoanToken, loanAmount, params);
    }

    //============================================ AAVE Logic ============================================
    function _borrowFromAave(ERC20 tokenToBorrow, uint256 amountToBorrow) internal {
        pool().borrow(address(tokenToBorrow), amountToBorrow, 2, 0, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
    }

    function _repayAaveDebt(ERC20 tokenToRepay, uint256 amountToRepay) internal {
        tokenToRepay.safeApprove(address(pool()), amountToRepay);
        pool().repay(address(tokenToRepay), amountToRepay, 2, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
    }

    function _simpleFlashLoan(
        ERC20 flashLoanToken,
        uint256 loanAmount,
        bytes memory params
    ) internal {
        address[] memory assets = new address[](1);
        assets[0] = address(flashLoanToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanAmount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;
        pool().flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }
}
