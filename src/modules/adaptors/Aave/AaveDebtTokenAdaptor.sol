// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { IPool } from "src/interfaces/external/IPool.sol";
import { DataTypes } from "src/interfaces/external/DataTypes.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";
import { Registry } from "src/Registry.sol";
import { Cellar } from "src/base/Cellar.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { console } from "@forge-std/Test.sol"; //TODO remove this

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

contract AaveDebtTokenAdaptor is BaseAdaptor {
    using SafeERC20 for ERC20;

    /*
        adaptorData = abi.encode( debt token address)
    */

    //============================================ Global Functions ===========================================
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Aave debtToken Adaptor V 0.0"));
    }

    function pool() internal pure returns (IPool) {
        return IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    }

    //============================================ Implement Base Functions ===========================================

    error AaveDebtTokenAdaptor__UserWithdrawNotAllowed();

    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        repayAaveDebt(ERC20(token.UNDERLYING_ASSET_ADDRESS()), assets);
    }

    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
        revert AaveDebtTokenAdaptor__UserWithdrawNotAllowed();
    }

    /**
     * @notice User withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address token = abi.decode(adaptorData, (address));
        return ERC20(token).balanceOf(msg.sender);
    }

    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        return ERC20(token.UNDERLYING_ASSET_ADDRESS());
    }

    //============================================ High Level Callable Functions ============================================

    error AaveDebtTokenAdaptor__DebtPositionsMustBeTracked(address untrackedDebtPosition);

    //TODO I think this function could accept the normal ERC20 asset(like USDC) and use pool().getReserveData(asset), but that reverted for me...
    function borrowFromAave(ERC20 debtTokenToBorrow, uint256 amountToBorrow) public {
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(address(debtTokenToBorrow))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert AaveDebtTokenAdaptor__DebtPositionsMustBeTracked(address(debtTokenToBorrow));

        pool().borrow(
            IAaveToken(address(debtTokenToBorrow)).UNDERLYING_ASSET_ADDRESS(),
            amountToBorrow,
            2,
            0,
            address(this)
        ); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
    }

    function repayAaveDebt(ERC20 tokenToRepay, uint256 amountToRepay) public {
        amountToRepay = _maxAvailable(tokenToRepay, amountToRepay);
        tokenToRepay.safeApprove(address(pool()), amountToRepay);
        pool().repay(address(tokenToRepay), amountToRepay, 2, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
    }

    function swapAndRepay(
        ERC20 tokenIn,
        ERC20 tokenToRepay,
        uint256 amountIn,
        SwapRouter.Exchange exchange,
        bytes memory params
    ) public {
        uint256 amountToRepay = swap(tokenIn, tokenToRepay, amountIn, exchange, params);
        repayAaveDebt(tokenToRepay, amountToRepay);
    }

    /**
     * @notice allows strategist to have Cellars take out flash loans.
     * @param loanToken address array of tokens to take out loans
     * @param loanAmount uint256 array of loan amounts for each token
     * @dev `modes` is always a zero array meaning that this flash loan can NOT take on new debt positions, it must be paid in full.
     */
    function flashLoan(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) public {
        require(loanToken.length == loanAmount.length, "Input length mismatch.");
        uint256[] memory modes = new uint256[](loanToken.length);
        pool().flashLoan(address(this), loanToken, loanAmount, modes, address(this), params, 0);
    }

    //============================================ AAVE Logic ============================================
}
