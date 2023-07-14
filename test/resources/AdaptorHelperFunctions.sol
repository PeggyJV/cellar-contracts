// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

// Aave V2
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";

// Morpho Aave V2
import { MorphoAaveV2ATokenAdaptor, IMorphoV2 } from "src/modules/adaptors/Morpho/MorphoAaveV2ATokenAdaptor.sol";
import { MorphoAaveV2DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2DebtTokenAdaptor.sol";

// Aave V3
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";

import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";

contract AdaptorHelperFunctions {
    // ========================================= General FUNCTIONS =========================================
    function _createBytesDataForSwapWithUniv3(
        ERC20 from,
        ERC20 to,
        uint24 poolFee,
        uint256 fromAmount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = poolFee;
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV3.selector, path, poolFees, fromAmount, 0);
    }

    function _createBytesDataForSwapWithUniv2(
        ERC20 from,
        ERC20 to,
        uint256 fromAmount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV2.selector, path, fromAmount, 0);
    }

    // ========================================= Aave V2 FUNCTIONS =========================================

    function _createBytesDataToLendOnAaveV2(
        ERC20 tokenToLend,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToWithdrawFromAaveV2(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrowFromAaveV2(
        ERC20 debtToken,
        uint256 amountToBorrow
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepayToAaveV2(
        ERC20 tokenToRepay,
        uint256 amountToRepay
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }

    function _createBytesDataToFlashLoanFromAaveV2(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    }

    // ========================================= Morpho Aave V2 FUNCTIONS =========================================

    function _createBytesDataToLendToMorphoAaveV2(
        address aToken,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(MorphoAaveV2ATokenAdaptor.depositToAaveV2Morpho.selector, aToken, amountToLend);
    }

    function _createBytesDataToWithdrawFromMorphoAaveV2(
        address aToken,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2ATokenAdaptor.withdrawFromAaveV2Morpho.selector,
                aToken,
                amountToWithdraw
            );
    }

    function _createBytesDataToBorrowFromMorphoAaveV2(
        address debtToken,
        uint256 amountToBorrow
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2DebtTokenAdaptor.borrowFromAaveV2Morpho.selector,
                debtToken,
                amountToBorrow
            );
    }

    function _createBytesDataToRepayToMorphoAaveV2(
        address debtToken,
        uint256 amountToRepay
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2DebtTokenAdaptor.repayAaveV2MorphoDebt.selector,
                debtToken,
                amountToRepay
            );
    }

    // ========================================= Aave V3 FUNCTIONS =========================================

    function _createBytesDataToLendOnAaveV3(
        ERC20 tokenToLend,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToChangeEModeOnAaveV3(uint8 category) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.changeEMode.selector, category);
    }

    function _createBytesDataToWithdrawFromAaveV3(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrowFromAaveV3(
        ERC20 debtToken,
        uint256 amountToBorrow
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepayToAaveV3(
        ERC20 tokenToRepay,
        uint256 amountToRepay
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }

    function _createBytesDataToFlashLoanFromAaveV3(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    }
}
