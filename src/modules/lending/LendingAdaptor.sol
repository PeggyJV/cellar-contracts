// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626, ERC20 } from "./ERC4626.sol";
import { Multicall } from "./Multicall.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Registry } from "src/Registry.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IGravity } from "../interfaces/IGravity.sol";
import { AddressArray } from "src/utils/AddressArray.sol";
import { Math } from "../utils/Math.sol";

import "../Errors.sol";

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 */
contract LendingAdaptor {
    constructor() {}

    function routeCalls(uint8[] functionsToCall, bytes[] memory callData) public {
        for (uint8 i = 0; i < functionsToCall.length; i++) {
            if (functionsToCall[i] == 1) {
                _depositToAave(callData[i]);
            }
        }
    }

    function _depositToAave(bytes memory callData) internal {
        (address[] memory tokens, uint256[] memory amounts) = abi.decode(callData, (address[], uint256[]));

        for (uint256 i = 0; i < tokens.length; i++) {}
    }
}
