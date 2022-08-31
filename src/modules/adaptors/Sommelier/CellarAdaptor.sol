// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Cellar Adaptor
 * @notice Cellars make delegate call to this contract in order to interact with other Cellar contracts.
 * @author crispymangoes
 */

contract CellarAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    /*
        adaptorData = abi.encode(Cellar cellar)
    */

    //============================================ Global Functions ===========================================

    //============================================ Implement Base Functions ===========================================
    function deposit(uint256 assets, bytes memory adaptorData) public override {
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        depositToCellar(cellar, assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData
    ) public override {
        if (receiver != address(this) && Cellar(msg.sender).blockExternalReceiver())
            revert("External receivers are not allowed.");
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        cellar.withdraw(assets, receiver, address(this));
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        return cellar.maxWithdraw(msg.sender);
    }

    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        return cellar.asset();
    }

    //============================================ Override Hooks ===========================================

    //============================================ High Level Callable Functions ============================================

    function depositToCellar(Cellar cellar, uint256 assets) public {
        assets = _maxAvailable(cellar.asset(), assets);
        cellar.asset().safeApprove(address(cellar), assets);
        cellar.deposit(assets, address(this));
    }

    function withdrawFromCellar(Cellar cellar, uint256 assets) public {
        cellar.withdraw(assets, address(this), address(this));
    }
}
