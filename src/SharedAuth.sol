// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { Registry } from "src/Registry.sol";

contract SharedAuth is Auth(address(0), Authority(address(0))) {
    Registry public immutable registry;

    constructor(Registry _registry) {
        registry = _registry;
    }

    function isAuthorized(address user, bytes4 functionSig) internal view override returns (bool) {
        Authority auth = Authority(registry.getAddress(3)); // Memoizing authority saves us a warm SLOAD, around 100 gas.

        // Checking if the caller is the owner only after calling the authority saves gas in most cases, but be
        // aware that this makes protected functions uncallable even to the owner if the authority is out of order.
        return
            (address(auth) != address(0) && auth.canCall(user, address(this), functionSig)) || user == registry.owner();
    }
}
