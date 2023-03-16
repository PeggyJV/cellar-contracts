// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { PositionlessAdaptor } from "src/modules/adaptors/PositionlessAdaptor.sol";

/**
 * @title 0x Adaptor
 * @notice Allows Cellars to swap with 0x.
 * @author crispymangoes
 */
contract ZeroXAdaptor is PositionlessAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
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

    function slippage() public pure returns (uint32) {
        return 0.95e4;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to make ERC20 swaps using 0x.
     */
    function swapWith0x(ERC20 tokenIn, ERC20 tokenOut, uint256 amount, bytes memory swapCallData) public {
        PriceRouter priceRouter = PriceRouter(Cellar(address(this)).registry().getAddress(2));

        tokenIn.safeApprove(target(), amount);

        if (priceRouter.isSupported(tokenIn)) {
            // If the asset in is supported, than require that asset out is also supported.
            if (!priceRouter.isSupported(tokenOut)) revert("Unsupported asset out.");
            // Save token balances.
            uint256 tokenInBalance = tokenIn.balanceOf(address(this));
            uint256 tokenOutBalance = tokenOut.balanceOf(address(this));

            // Perform Swap.
            target().functionCall(swapCallData);

            uint256 tokenInAmountIn = tokenInBalance - tokenIn.balanceOf(address(this));
            uint256 tokenOutAmountOut = tokenOut.balanceOf(address(this)) - tokenOutBalance;

            uint256 tokenInValueOut = priceRouter.getValue(tokenOut, tokenOutAmountOut, tokenIn);

            if (tokenInValueOut < tokenInAmountIn.mulDivDown(slippage(), 1e4)) revert("Slippage Revert");
        } else {
            // Token In is not supported by price router, so we know it is atleast not the Cellars Reserves,
            // or a prominent asset, so skip value in vs value out check.
            target().functionCall(swapCallData);
        }

        // Insure spender has zero approval.
        _revokeExternalApproval(tokenIn, target());
    }
}
