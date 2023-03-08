// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { PositionlessAdaptor } from "src/modules/adaptors/PositionlessAdaptor.sol";

/**
 * @title 0x Adaptor
 * @notice Allows Cellars to swap with 0x.
 * @author crispymangoes
 */
contract ZeroXAdaptor is PositionlessAdaptor {
    using SafeTransferLib for ERC20;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // expose the swap function to strategists during rebalances.
    //====================================================================

    /**
     * @notice Attempted to pass in the Cellar Address as the spender or swapTarget.
     */
    error ZeroXAdaptor__InvalidAddressArgument();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("0x Adaptor V 0.0"));
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to make ERC20 swaps using 0x.
     */
    function swapWith0x(
        ERC20 tokenIn,
        uint256 amount,
        address spender,
        address swapTarget,
        bytes memory swapCallData
    ) public {
        // Revert if address inputs are the Cellar.
        if (spender == address(this) || swapTarget == address(this)) revert ZeroXAdaptor__InvalidAddressArgument();
        tokenIn.safeApprove(spender, amount);

        swapTarget.functionCall(swapCallData);

        // Insure spender has zero approval.
        if (tokenIn.allowance(address(this), spender) > 0) tokenIn.safeApprove(spender, 0);
    }
}
