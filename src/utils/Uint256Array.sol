// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/**
 * @notice A library to extend the address array data type.
 */
library Uint256Array {
    // =========================================== ADDRESS STORAGE ===========================================

    /**
     * @notice Add an address to the array at a given index.
     * @param array address array to add the address to
     * @param index index to add the address at
     * @param value address to add to the array
     */
    function add(
        uint256[] storage array,
        uint256 index,
        uint256 value
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
     * @notice Remove a uint256 from the array at a given index.
     * @param array uint256 array to remove the uint256 from
     * @param index index to remove the uint256 at
     */
    function remove(uint256[] storage array, uint256 index) internal {
        uint256 len = array.length;

        require(index < len, "Index out of bounds");

        for (uint256 i = index; i < len - 1; i++) array[i] = array[i + 1];

        array.pop();
    }

    /**
     * @notice Check whether an array contains an uint256.
     * @param array uint256 array to check
     * @param value uint256 to check for
     */
    function contains(uint256[] storage array, uint256 value) internal view returns (bool) {
        for (uint256 i; i < array.length; i++) if (value == array[i]) return true;

        return false;
    }
}
