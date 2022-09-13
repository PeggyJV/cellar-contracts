// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";
import { LiquityAdaptor } from "src/modules/adaptors/Liquity/LiquityAdaptor.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

contract LiquityAdaptorCollateral is BaseAdaptor, LiquityAdaptor {
    using SafeTransferLib for ERC20;

    /*
        adaptorData = abi.encode(aToken address)
    */

    //============================================ Global Functions ===========================================
    function pool() internal pure returns (address) {
        return (0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    }

    //============================================ Implement Base Functions ===========================================
    function deposit(uint256 assets, bytes memory adaptorData) public override {
        revert("user deposits not allowed");
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData
    ) public override {
        revert("User withdraws not allowed");
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // Go to TroveManager  https://etherscan.io/address/0xa39739ef8b0231dbfa0dcda07d7e29faabcf4bb2#readContract
        // Look at Troves(msg.sender) -> coll
        //roveManager()
    }

    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        return ERC20(token.UNDERLYING_ASSET_ADDRESS());
    }

    //============================================ Override Hooks ===========================================
    function afterHook(bytes memory hookData) public view virtual override returns (bool) {
        //TODO  calculate position LTV
        //TODO in cellar code, withdrawableFrom should be checked for every position right before the withdraw.
    }
}
