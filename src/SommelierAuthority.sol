// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { Authority } from "@solmate/auth/Auth.sol";
import { SharedAuth } from "src/SharedAuth.sol";
import { Registry } from "src/Registry.sol";

contract SommelierAuthority is Authority, SharedAuth {
    // maps user => target => functionSig => bool
    mapping(address => mapping(address => mapping(bytes4 => bool))) private strategyProviderAdmin; //give special permission to SPs on mainnet

    constructor(Registry _registry) SharedAuth(_registry) {}

    function canCall(
        address user,
        address target,
        bytes4 functionSig
    ) external view returns (bool) {
        //TODO is it possible for SPs to opt out of using the gravity bridge entirely?
        // if call is the gravity bridge, allow calls regardless
        if (user == registry.getAddress(0)) return true;
        // check if user has the privealge to call functionSig on target
        else return strategyProviderAdmin[user][target][functionSig];
    }

    /**
     * @notice Allows caller to specify which function sigs a user can call on a specfic target
     * @param user address to grant calling privelages to
     * @param target address user can make calls to
     * @param functionSigs bytes4 array of all the funciton signatures to add to the users privelages
     */
    function grantPrivelages(
        address user,
        address target,
        bytes4[] memory functionSigs
    ) public requiresAuth {
        for (uint256 i = 0; i < functionSigs.length; i++) {
            if (!strategyProviderAdmin[user][target][functionSigs[i]])
                strategyProviderAdmin[user][target][functionSigs[i]] = true;
        }
    }

    /**
     * @notice Allows caller to specify which function sigs a user can no longer call on a specfic target
     * @param user address to revoke calling privelages from
     * @param target address user is losing privelages to call
     * @param functionSigs bytes4 array of all the funciton signatures to remove from the users privelages
     */
    function revokePrivelages(
        address user,
        address target,
        bytes4[] memory functionSigs
    ) public requiresAuth {
        for (uint256 i = 0; i < functionSigs.length; i++) {
            if (strategyProviderAdmin[user][target][functionSigs[i]])
                strategyProviderAdmin[user][target][functionSigs[i]] = false;
        }
    }
}
