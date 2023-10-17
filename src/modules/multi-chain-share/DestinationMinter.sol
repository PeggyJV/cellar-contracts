// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { Math } from "src/utils/Math.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract DestinationMinter is ERC20 {
    // Supplied by a special CCIP Recieve to create the contract
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) {}
}
