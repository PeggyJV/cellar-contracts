// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626, ERC20 } from "./ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

error USR_InvalidPositionType();

enum PositionType {
    ERC20,
    ERC4626,
    Cellar
}

library PositionLib {
    using SafeTransferLib for ERC20;

    function asset(address position, PositionType positionType) internal view returns (ERC20) {
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            return ERC4626(position).asset();
        } else if (positionType == PositionType.ERC20) {
            return ERC20(position);
        } else {
            revert USR_InvalidPositionType();
        }
    }

    function balanceOf(
        address position,
        PositionType positionType,
        address owner
    ) internal view returns (uint256 balance) {
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            balance = ERC4626(position).maxWithdraw(owner);
        } else if (positionType == PositionType.ERC20) {
            balance = ERC20(position).balanceOf(owner);
        } else {
            revert USR_InvalidPositionType();
        }
    }

    function deposit(
        address position,
        PositionType positionType,
        uint256 assets
    ) internal {
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            ERC4626(position).asset().safeApprove(position, assets);
            ERC4626(position).deposit(assets, address(this));
        } else if (positionType != PositionType.ERC20) {
            revert USR_InvalidPositionType();
        }
    }

    function withdraw(
        address position,
        PositionType positionType,
        uint256 assets,
        address receiver
    ) internal {
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            ERC4626(position).withdraw(assets, receiver, address(this));
        } else if (positionType == PositionType.ERC20) {
            if (receiver != address(this)) ERC20(position).safeTransfer(receiver, assets);
        } else {
            revert USR_InvalidPositionType();
        }
    }
}
