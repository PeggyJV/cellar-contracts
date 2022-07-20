// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626, ERC20 } from "src/base/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

/**
 * @title Base Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

abstract contract BaseAdaptor {
    function deposit(uint256 assets, bytes memory adaptorData) public virtual;

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData
    ) public virtual;

    function balanceOf(bytes memory adaptorData) public view virtual returns (uint256);

    function assetOf(bytes memory adaptorData) public view virtual returns (ERC20);

    function beforeHook(bytes memory hookData) public view virtual returns (bool) {
        return true;
    }

    function afterHook(bytes memory hookData) public view virtual returns (bool) {
        return true;
    }

    function _maxAvailable(ERC20 token, uint256 amount) internal view virtual returns (uint256) {
        if (amount == type(uint256).max) return token.balanceOf(address(this));
        else return amount;
    }
}
