// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

interface IUpgradeableProxy {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     *  @dev   Event emitted when a new admin is removed from the Conduit.
     *  @param usr The address of the user to remove.
     */
    event Deny(address indexed usr);

    /**
     *  @dev   Event emitted when a new admin is added to the Conduit.
     *  @param usr The address of the user to add.
     */
    event Rely(address indexed usr);

    /**
     *  @dev   Event emitted when the implementation address is changed.
     *  @param implementation_ The address of the new implementation.
     */
    event SetImplementation(address indexed implementation_);

    /**********************************************************************************************/
    /*** Storage Variables                                                                      ***/
    /**********************************************************************************************/

    /**
     *  @dev   Returns the address of the implementation contract.
     *  @return implementation_ The address of the implementation contract.
     */
    function implementation() external view returns (address implementation_);

    /**
     *  @dev    Returns a 0 or 1 depending on if the user has been added as an admin.
     *  @return relied The value of the user's admin status.
     */
    function wards(address user) external view returns (uint256 relied);

    /**********************************************************************************************/
    /*** Administrative Functions                                                               ***/
    /**********************************************************************************************/

    /**
     *  @dev   Function to remove an addresses admin permissions.
     *  @param usr The address of the admin.
     */
    function deny(address usr) external;

    /**
     *  @dev   Function to give an address admin permissions.
     *  @param usr The address of the new admin.
     */
    function rely(address usr) external;

    /**
     *  @dev   Function to set the implementation address of the proxy.
     *  @param implementation_ The address of the new implementation.
     */
    function setImplementation(address implementation_) external;

}
