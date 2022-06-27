// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626, ERC20 } from "./ERC4626.sol";
import { Cellar } from "./Cellar.sol";

//TODO move PositionType struct into here?
library PositionLib {
    function asset(ERC4626 vault, Cellar.PositionType positionType) internal view returns (ERC20) {
        if (positionType == Cellar.PositionType.ERC4626 || positionType == Cellar.PositionType.Cellar) {
            return vault.asset();
        } else if (positionType == Cellar.PositionType.ERC20) {
            return ERC20(address(vault));
        } else {
            revert("Unsupported Position Type");
        }
    }

    function maxWithdraw(
        ERC4626 vault,
        Cellar.PositionType positionType,
        address holder
    ) internal view returns (uint256) {
        if (positionType == Cellar.PositionType.ERC4626 || positionType == Cellar.PositionType.Cellar) {
            return vault.maxWithdraw(holder);
        } else if (positionType == Cellar.PositionType.ERC20) {
            return ERC20(address(vault)).balanceOf(holder);
        } else {
            revert("Unsupported Position Type");
        }
    }

    function withdraw(
        ERC4626 vault,
        Cellar.PositionType positionType,
        uint256 assets,
        address receiver,
        address owner
    ) internal returns (uint256 shares) {
        if (positionType == Cellar.PositionType.ERC4626 || positionType == Cellar.PositionType.Cellar) {
            shares = vault.withdraw(assets, receiver, owner);
        } else if (positionType == Cellar.PositionType.ERC20) {
            //since we dont need to actually do anything just return how many tokens the cellar has? Assumes the amount of tokens the cellar has is equal to the amount of shares it has
            shares = ERC20(address(vault)).balanceOf(owner);
        } else {
            revert("Unsupported Position Type");
        }
    }

    function deposit(
        ERC4626 vault,
        Cellar.PositionType positionType,
        uint256 assets,
        address receiver
    ) internal returns (uint256 shares) {
        if (positionType == Cellar.PositionType.ERC4626 || positionType == Cellar.PositionType.Cellar) {
            shares = vault.deposit(assets, receiver);
        } else if (positionType == Cellar.PositionType.ERC20) {
            //since we dont need to actually do anything just return how many tokens the cellar has? Assumes the amount of tokens the cellar has is equal to the amount of shares it has
            shares = ERC20(address(vault)).balanceOf(receiver);
        } else {
            revert("Unsupported Position Type");
        }
    }
}
