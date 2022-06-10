// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

// TODO: add natspec

/**
 * @notice A library to extend the address array data type.
 */
library AddressArray {
    function add(
        address[] storage array,
        uint256 index,
        address value
    ) internal {
        uint256 len = array.length;

        array.push(array[len - 1]);

        for (uint256 i = len - 1; i > index; i--) array[i] = array[i - 1];

        array[index] = value;
    }

    function remove(address[] storage array, uint256 index) internal {
        uint256 len = array.length;

        require(index < len, "Index out of bounds");

        for (uint256 i = index; i < len - 1; i++) array[i] = array[i + 1];

        array.pop();
    }

    /**
     * @notice Remove the first occurrence of a value in an array.
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

    function contains(address[] storage array, address value) internal view returns (bool) {
        for (uint256 i; i < array.length; i++) if (value == array[i]) return true;

        return false;
    }
}
