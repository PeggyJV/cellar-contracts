// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { IUpgradeableProxied } from "./interfaces/IUpgradeableProxied.sol";

contract UpgradeableProxied is IUpgradeableProxied {

    // Placeholder for implementation address, bytes32 so implementation address can never
    // be set by the implementation contract.
    bytes32 private slot0;

    mapping (address => uint256) public override wards;

}
