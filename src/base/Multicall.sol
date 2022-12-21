// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import { IMulticall } from "src/interfaces/IMulticall.sol";

/**
 * @title Multicall
 * @notice Enables calling multiple methods in a single call to the contract
 * From: https://github.com/Uniswap/v3-periphery/blob/1d69caf0d6c8cfeae9acd1f34ead30018d6e6400/contracts/base/Multicall.sol
 */
abstract contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data) public payable override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                // solhint-disable-next-line reason-string
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}
