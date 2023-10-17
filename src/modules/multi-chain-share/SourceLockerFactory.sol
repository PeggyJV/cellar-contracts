// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { SourceLocker } from "./SourceLocker.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract SourceLockerFactory is Owned {
    address public destinationMinterFactory;

    constructor(address _owner) Owned(_owner) {}

    function deploy(ERC4626 target) external onlyOwner {
        // Deploy a new Source Target
        // CCIP Send new Source Target address, target.name(), target.symbol(), target.decimals() to DestinationMinterFactory.
        // Done
    }

    // CCIP Receive function will accept new DestinationMinter address, and corresponding source locker, and call SourceLocker:setTargetDestination()

    // TODO function to withdraw ERC20s from this, so owner can withdraw LINK.
}
