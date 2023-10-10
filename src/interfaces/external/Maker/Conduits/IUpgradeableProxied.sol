// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

interface IUpgradeableProxied {

    /**
     *  @dev    Returns a 0 or 1 depending on if the user has been added as an admin.
     *  @return relied The value of the user's admin status.
     */
    function wards(address user) external view returns (uint256 relied);

}
