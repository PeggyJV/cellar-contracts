// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract SourceLocker {
    ERC20 public immutable shareToken;
    address public immutable factory;
    address public targetDestination;

    constructor(ERC20 _shareToken, address _factory) {
        shareToken = _shareToken;
        factory = _factory;
    }

    function setTargetDestination(address _targetDestination) external {
        if (msg.sender != factory) revert("no no no");
        if (targetDestination != address(0)) revert("target already set");

        targetDestination = _targetDestination;
    }

    // CCIP Receieve sender must be targetDestination
    // transfer shareToken amount and to to

    // on shareToken lock, transfer shareTokens in, and CCIP Send to targetDestination amount and to address
}
