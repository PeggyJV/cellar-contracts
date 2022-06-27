// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626, ERC20 } from "./ERC4626.sol";
import { Cellar } from "./Cellar.sol";

enum PositionType {
    ERC20,
    ERC4626,
    Cellar
}

library PositionLib {
    function asset(address position, PositionType positionType) internal view returns (ERC20) {
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            return ERC4626(position).asset();
        } else if (positionType == PositionType.ERC20) {
            return ERC20(position);
        } else {
            revert("Unsupported Position Type");
        }
    }

    function maxWithdraw(
        address position,
        PositionType positionType,
        address holder
    ) internal view returns (uint256) {
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            return ERC4626(position).maxWithdraw(holder);
        } else if (positionType == PositionType.ERC20) {
            return ERC20(position).balanceOf(holder);
        } else {
            revert("Unsupported Position Type");
        }
    }

    function balanceOf(
        address position,
        PositionType positionType,
        address holder
    ) internal view returns (uint256) {
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            return ERC4626(position).balanceOf(holder);
        } else if (positionType == PositionType.ERC20) {
            return ERC20(position).balanceOf(holder);
        } else {
            revert("Unsupported Position Type");
        }
    }

    function withdraw(
        address position,
        PositionType positionType,
        uint256 assets,
        address receiver,
        address owner
    ) internal returns (uint256 shares) {
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            shares = ERC4626(position).withdraw(assets, receiver, owner);
        } else if (positionType == PositionType.ERC20) {
            //since we dont need to actually do anything just return how many tokens the cellar has? Assumes the amount of tokens the cellar has is equal to the amount of shares it has
            shares = ERC20(position).balanceOf(owner);
        } else {
            revert("Unsupported Position Type");
        }
    }

    function deposit(
        address position,
        PositionType positionType,
        uint256 assets,
        address receiver
    ) internal returns (uint256 shares) {
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            shares = ERC4626(position).deposit(assets, receiver);
        } else if (positionType == PositionType.ERC20) {
            //since we dont need to actually do anything just return how many tokens the cellar has? Assumes the amount of tokens the cellar has is equal to the amount of shares it has
            shares = ERC20(position).balanceOf(receiver);
        } else {
            revert("Unsupported Position Type");
        }
    }
}
