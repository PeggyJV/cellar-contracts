// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { IPool } from "@aave/interfaces/IPool.sol";
import { ERC4626, ERC20 } from "src/base/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 */
contract LendingAdaptor {
    using SafeTransferLib for ERC20;

    function routeCalls(uint8[] memory functionsToCall, bytes[] memory callData) public {
        for (uint8 i = 0; i < functionsToCall.length; i++) {
            if (functionsToCall[i] == 1) {
                _depositToAave(callData[i]);
            } else if (functionsToCall[i] == 2) {
                _borrowFromAave(callData[i]);
            } else if (functionsToCall[i] == 3) {
                _repayAaveDebt(callData[i]);
            }
        }
    }

    //TODO might need to add a check that toggles use reserve as collateral
    function _depositToAave(bytes memory callData) internal {
        (ERC20[] memory tokens, uint256[] memory amounts) = abi.decode(callData, (ERC20[], uint256[]));
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].safeApprove(address(pool), amounts[i]);
            pool.deposit(address(tokens[i]), amounts[i], address(this), 0);
        }
    }

    function _borrowFromAave(bytes memory callData) internal {
        (ERC20[] memory tokens, uint256[] memory amounts) = abi.decode(callData, (ERC20[], uint256[]));
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        for (uint256 i = 0; i < tokens.length; i++) {
            pool.borrow(address(tokens[i]), amounts[i], 2, 0, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
        }
    }

    function _repayAaveDebt(bytes memory callData) internal {
        (ERC20[] memory tokens, uint256[] memory amounts) = abi.decode(callData, (ERC20[], uint256[]));
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].safeApprove(address(pool), amounts[i]);
            pool.repay(address(tokens[i]), amounts[i], 2, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
        }
    }
}
