// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { Math } from "src/utils/Math.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract DestinationMinterFactory is Owned {
    address public immutable sourceLockerFactory;

    constructor(address _owner, address _sourceLockerFactory) Owned(_owner) {
        sourceLockerFactory = _sourceLockerFactory;
    }

    // CCIP Recieve accepts message from SourceLockerFactory with following values.
    //new Source Target address, target.name(), target.symbol(), target.decimals()
    // Deploys a new Destination Minter
    // CCIP sends message back to SourceLockerFactory with new DestinationMinter address, and corresponding source locker
    // TODO function to withdraw ERC20s from this, so owner can withdraw LINK.
}
