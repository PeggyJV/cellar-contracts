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

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("0x Adaptor V 1.0"));
    }

    /**
     * @notice Address of the current 0x swap target on Mainnet ETH.
     */
    function target() public pure returns (address) {
        return 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    }

    //============================================ Strategist Functions ===========================================

    // TODO check value in vs value out
    // Skip the check if we dont have pricing for the input token
    /**
     * @notice Allows strategists to make ERC20 swaps using 0x.
     */
    function swapWith0x(ERC20 tokenIn, uint256 amount, bytes memory swapCallData) public {
        tokenIn.safeApprove(target(), amount);

        target().functionCall(swapCallData);

        // Insure spender has zero approval.
        _revokeExternalApproval(tokenIn, target());
    }
}
