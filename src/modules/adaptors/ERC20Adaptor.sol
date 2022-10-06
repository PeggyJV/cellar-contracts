// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Cellar Adaptor
 * @notice Cellars make delegate call to this contract in order to interact with other Cellar contracts.
 * @author crispymangoes
 */

contract ERC20Adaptor is BaseAdaptor {
    using SafeERC20 for ERC20;

    /*
        adaptorData = abi.encode(ERC20 token)
    */

    //============================================ Global Functions ===========================================

    //============================================ Implement Base Functions ===========================================
    function deposit(uint256 assets, bytes memory adaptorData) public override {
        // Nothing to deposit since caller is already holding the ERC20.
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData
    ) public override {
        if (receiver != address(this) && Cellar(address(this)).blockExternalReceiver())
            revert("External receivers are not allowed.");
        ERC20 token = abi.decode(adaptorData, (ERC20));
        token.safeTransfer(receiver, assets);
    }

    function withdrawableFrom(bytes memory adaptorData) public view override returns (uint256) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token.balanceOf(msg.sender);
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token.balanceOf(msg.sender);
    }

    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    //============================================ Override Hooks ===========================================

    //============================================ High Level Callable Functions ============================================
}
