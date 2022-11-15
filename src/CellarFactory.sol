// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Owned, ERC20, SafeTransferLib, Address } from "src/base/Cellar.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

contract CellarFactory is Owned {
    using SafeTransferLib for ERC20;
    using Clones for address;
    using Address for address;

    constructor() Owned(msg.sender) {}

    function deploy(
        address implementation,
        bytes calldata initializeCallData,
        ERC20 asset,
        uint256 initialDeposit
    ) external onlyOwner {
        address clone = implementation.clone();
        clone.functionCall(initializeCallData);
        asset.safeTransferFrom(msg.sender, address(this), initialDeposit);
        asset.safeApprove(clone, initialDeposit);
        Cellar(clone).deposit(initialDeposit, address(this));
        //TODO I guess we could transfer the shares out? Or do we wanna "lock" them in here to always have liquidity in the cellars?
    }
}
