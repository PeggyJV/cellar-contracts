// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

/**
 * @notice A library to extend the uint32 array data type.
 */
library Uint32Array {
    // =========================================== ADDRESS STORAGE ===========================================

    /**
     * @notice Add an uint32 to the array at a given index.
     * @param array uint32 array to add the uint32 to
     * @param index index to add the uint32 at
     * @param value uint32 to add to the array
     */
    function add(uint32[] storage array, uint32 index, uint32 value) internal {
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
     * @notice Remove a uint32 from the array at a given index.
     * @param array uint32 array to remove the uint32 from
     * @param index index to remove the uint32 at
     */
    function remove(uint32[] storage array, uint32 index) internal {
        uint256 len = array.length;

        require(index < len, "Index out of bounds");

        for (uint256 i = index; i < len - 1; i++) array[i] = array[i + 1];

        array.pop();
    }

    /**
     * @notice Check whether an array contains an uint32.
     * @param array uint32 array to check
     * @param value uint32 to check for
     */
    function contains(uint32[] storage array, uint32 value) internal view returns (bool) {
        for (uint256 i; i < array.length; i++) if (value == array[i]) return true;

        return false;
    }
}
