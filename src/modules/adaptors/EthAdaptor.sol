// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";

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
    function WETH() internal pure returns (IWETH9) {
        return IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    //============================================ Implement Base Functions ===========================================
    function deposit(uint256 assets, bytes memory) public override {
        // Takes WETH and unwraps it.
        WETH().withdraw(assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory
    ) public override {
        //TODO add receiver check.
        // Takes ETH and wraps it
        WETH().deposit{ value: assets }();
        WETH().transfer(receiver, assets);
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // Queries msg.sender ETH balance
        //return
    }

    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        // return
    }

    //============================================ High Level Callable Functions ============================================
    //TODO might need to add a check that toggles use reserve as collateral
    function wrap() public {}

    function unwrap() public {}
}
