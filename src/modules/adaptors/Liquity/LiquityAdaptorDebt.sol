// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar, Registry, PriceRouter } from "src/base/Cellar.sol";
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

contract LiquityAdaptorDebt is BaseAdaptor, LiquityAdaptor {
    using SafeTransferLib for ERC20;

    //============================================ Implement Base Functions ===========================================
    function deposit(uint256 assets, bytes memory adaptorData) public override {
        revert("Unable to repay debt.");
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData
    ) public override {
        revert("Note Allowed to withdraw from a trove");
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (uint256 debt, , , , ) = troveManager().Troves(msg.sender);
        return debt;
    }

    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        return LUSD();
    }

    //============================================ Override Hooks ===========================================
    function afterHook(bytes memory hookData) public view virtual override returns (bool) {
        PriceRouter priceRouter = PriceRouter(Cellar(msg.sender).registry().getAddress(2));
        uint256 minICR = abi.decode(hookData, (uint256));
        uint256 price = priceRouter.getExchangeRate(WETHERC20(), LUSD());
        uint256 ICR = troveManager().getCurrentICR(msg.sender, price);
        return ICR >= minICR;
    }
}
