// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title 0x Adaptor
 * @notice Allows Cellars to swap with 0x.
 * @author crispymangoes
 */
contract ZeroXAdaptor is BaseAdaptor {
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

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed.
     */
    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice There is no underlying position so return zero.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice There is no underlying position so return zero.
     */
    function balanceOf(bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice There is no underlying position so return zero address.
     */
    function assetOf(bytes memory) public pure override returns (ERC20) {
        return ERC20(address(0));
    }

    /**
     * @notice There is no underlying position so return false.
     */
    function isDebt() public pure override returns (bool) {
        return false;
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
