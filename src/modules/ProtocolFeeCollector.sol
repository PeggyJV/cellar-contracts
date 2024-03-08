// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { Owned } from "@solmate/auth/Owned.sol";

/**
 * @title Protocol Fee Collector
 * @notice Collects protocol fees on chains where the gravity bridge does not exist.
 * @notice Future contracts can implement `sendToCosmos` and actually send the fees to Cosmos.
 * @author crispymangoes
 */
contract ProtocolFeeCollector is Owned {
    using SafeTransferLib for ERC20;

    constructor(address _owner) Owned(_owner) {}

    /**
     * @notice Implements the Gravity Bridge `sendToCosmos` function, but
     *         just holds ERC20s in contract.
     */
    function sendToCosmos(address asset, bytes32, uint256 amount) external {
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Allows owner to withdraw ERC20s from this contract.
     */
    function withdrawERC20(ERC20 asset, address to, uint256 amount) external onlyOwner {
        asset.safeTransfer(to, amount);
    }
}
