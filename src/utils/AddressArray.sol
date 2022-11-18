// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";

/**
 * @notice A library to extend the address array data type.
 */
library AddressArray {
    // =========================================== ADDRESS STORAGE ===========================================

    /**
     * @notice Add an address to the array at a given index.
     * @param array address array to add the address to
     * @param index index to add the address at
     * @param value address to add to the array
     */
    function add(
        address[] storage array,
        uint256 index,
        address value
    ) internal {
        uint256 len = array.length;

        if (len > 0) {
            array.push(array[len - 1]);

            for (uint256 i = len - 1; i > index; i--) array[i] = array[i - 1];

            array[index] = value;
        } else {
            array.push(value);
        }
    }

    /**
     * @notice Remove an address from the array at a given index.
     * @param array address array to remove the address from
     * @param index index to remove the address at
     */
    function remove(address[] storage array, uint256 index) internal {
        uint256 len = array.length;

        require(index < len, "Index out of bounds");

        for (uint256 i = index; i < len - 1; i++) array[i] = array[i + 1];

        array.pop();
    }

    /**
     * @notice Remove the first occurrence of a value in an array.
     * @param array address array to remove the address from
     * @param value address to remove from the array
     */
    function remove(address[] storage array, address value) internal {
        uint256 len = array.length;

        for (uint256 i; i < len; i++)
            if (array[i] == value) {
                for (i; i < len - 1; i++) array[i] = array[i + 1];

                array.pop();

                return;
            }

        revert("Value not found");
    }

    /**
     * @notice Check whether an array contains an address.
     * @param array address array to check
     * @param value address to check for
     */
    function contains(address[] storage array, address value) internal view returns (bool) {
        for (uint256 i; i < array.length; i++) if (value == array[i]) return true;

        return false;
    }
}
