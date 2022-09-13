// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

contract EthAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    /*
        adaptorData = abi.encode(aToken address)
    */

    //============================================ Global Functions ===========================================
    function borrowerOperations() internal pure returns (address) {
        return 0x24179CD81c9e782A4096035f7eC97fB8B783e007;
    }

    function troveManager() internal pure returns (address) {
        return 0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2;
    }

    function LUSD() internal pure returns (ERC20) {
        return ERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    }

    //============================================ Implement Base Functions ===========================================
    function deposit(uint256 assets, bytes memory adaptorData) public override {
        //Takes WETH and unwraps it
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData
    ) public override {
        // Takes ETH and wraps it
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // Queries msg.sender ETH balance
    }

    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        // Return WETH address?
        // Deposit takes WETH and converts it to ETH
        //Withdraws take ETH and give WETH
        // Either method uses WETH as Input and Output.
    }

    //============================================ High Level Callable Functions ============================================
    //TODO might need to add a check that toggles use reserve as collateral
    function wrap() public {}

    function unwrap() public {}
}
