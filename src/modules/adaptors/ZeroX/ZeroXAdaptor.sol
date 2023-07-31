// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

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

    /**
     * @notice The 0x swap target contract on current network.
     * @notice For mainnet use 0xDef1C0ded9bec7F1a1670819833240f027b25EfF.
     */
    address public immutable target;

    constructor(address _target) {
        target = _target;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("0x Adaptor V 1.1"));
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to make ERC20 swaps using 0x.
     */
    function swapWith0x(ERC20 tokenIn, ERC20 tokenOut, uint256 amount, bytes memory swapCallData) public {
        PriceRouter priceRouter = Cellar(address(this)).priceRouter();

        tokenIn.safeApprove(target, amount);

        if (priceRouter.isSupported(tokenIn)) {
            // If the asset in is supported, than require that asset out is also supported.
            if (!priceRouter.isSupported(tokenOut)) revert BaseAdaptor__PricingNotSupported(address(tokenOut));
            // Save token balances.
            uint256 tokenInBalance = tokenIn.balanceOf(address(this));
            uint256 tokenOutBalance = tokenOut.balanceOf(address(this));

            // Perform Swap.
            target.functionCall(swapCallData);

            uint256 tokenInAmountIn = tokenInBalance - tokenIn.balanceOf(address(this));
            uint256 tokenOutAmountOut = tokenOut.balanceOf(address(this)) - tokenOutBalance;

            uint256 tokenInValueOut = priceRouter.getValue(tokenOut, tokenOutAmountOut, tokenIn);

            if (tokenInValueOut < tokenInAmountIn.mulDivDown(slippage(), 1e4)) revert BaseAdaptor__Slippage();
        } else {
            // Token In is not supported by price router, so we know it is at least not the Cellars Reserves,
            // or a prominent asset, so skip value in vs value out check.
            target.functionCall(swapCallData);
        }

        // Insure spender has zero approval.
        _revokeExternalApproval(tokenIn, target);
    }
}
