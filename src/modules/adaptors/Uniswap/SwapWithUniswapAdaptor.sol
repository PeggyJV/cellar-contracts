// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { PositionlessAdaptor } from "src/modules/adaptors/PositionlessAdaptor.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";

/**
 * @title SwapWithUniswapAdaptor
 * @notice Allows Cellars to swap using Uniswap V2, or V3.
 * @author crispymangoes
 */
contract SwapWithUniswapAdaptor is PositionlessAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // expose the swap functions to strategists during rebalances.
    //====================================================================

    /**
     * @notice The Uniswap V2 Router contract on current network.
     * @notice For mainnet use 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D.
     */
    IUniswapV2Router public immutable uniswapV2Router;

    /**
     * @notice The Uniswap V3 Router contract on current network.
     * @notice For mainnet use 0xE592427A0AEce92De3Edee1F18E0157C05861564.
     */
    IUniswapV3Router public immutable uniswapV3Router;

    constructor(address _v2Router, address _v3Router) {
        uniswapV2Router = IUniswapV2Router(_v2Router);
        uniswapV3Router = IUniswapV3Router(_v3Router);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Swap With Uniswap Adaptor V 0.1"));
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Perform a swap using Uniswap V2.
     * @dev Allows for a blind swap, if type(uint256).max is used for the amount.
     */
    function swapWithUniV2(address[] memory path, uint256 amount, uint256 amountOutMin) public {
        PriceRouter priceRouter = Cellar(address(this)).priceRouter();

        ERC20 tokenIn = ERC20(path[0]);
        ERC20 tokenOut = ERC20(path[path.length - 1]);

        amount = _maxAvailable(tokenIn, amount);

        // Approve assets to be swapped through the router.
        tokenIn.safeApprove(address(uniswapV2Router), amount);

        if (priceRouter.isSupported(tokenIn)) {
            // If the asset in is supported, than require that asset out is also supported.
            if (!priceRouter.isSupported(tokenOut)) revert BaseAdaptor__PricingNotSupported(address(tokenOut));
            // Save token balances.
            uint256 tokenInBalance = tokenIn.balanceOf(address(this));

            // Execute the swap.
            uint256[] memory amountsOut = uniswapV2Router.swapExactTokensForTokens(
                amount,
                amountOutMin,
                path,
                address(this),
                block.timestamp + 60
            );
            uint256 tokenOutAmountOut = amountsOut[amountsOut.length - 1];

            uint256 tokenInAmountIn = tokenInBalance - tokenIn.balanceOf(address(this));

            uint256 tokenInValueOut = priceRouter.getValue(tokenOut, tokenOutAmountOut, tokenIn);

            if (tokenInValueOut < tokenInAmountIn.mulDivDown(slippage(), 1e4)) revert BaseAdaptor__Slippage();
        } else {
            // Token In is not supported by price router, so we know it is at least not the Cellars Reserves,
            // or a prominent asset, so skip value in vs value out check.
            // Execute the swap.
            uniswapV2Router.swapExactTokensForTokens(amount, amountOutMin, path, address(this), block.timestamp + 60);
        }

        // Insure spender has zero approval.
        _revokeExternalApproval(tokenIn, address(uniswapV2Router));
    }

    /**
     * @notice Perform a swap using Uniswap V3.
     * @dev Allows for a blind swap, if type(uint256).max is used for the amount.
     */
    function swapWithUniV3(
        address[] memory path,
        uint24[] memory poolFees,
        uint256 amount,
        uint256 amountOutMin
    ) public {
        PriceRouter priceRouter = Cellar(address(this)).priceRouter();

        ERC20 tokenIn = ERC20(path[0]);
        ERC20 tokenOut = ERC20(path[path.length - 1]);

        amount = _maxAvailable(tokenIn, amount);

        // Approve assets to be swapped through the router.
        tokenIn.safeApprove(address(uniswapV3Router), amount);

        // Encode swap parameters.
        bytes memory encodePackedPath = abi.encodePacked(address(path[0]));
        for (uint256 i = 1; i < path.length; i++)
            encodePackedPath = abi.encodePacked(encodePackedPath, poolFees[i - 1], path[i]);

        if (priceRouter.isSupported(tokenIn)) {
            // If the asset in is supported, than require that asset out is also supported.
            if (!priceRouter.isSupported(tokenOut)) revert BaseAdaptor__PricingNotSupported(address(tokenOut));
            // Save token balances.
            uint256 tokenInBalance = tokenIn.balanceOf(address(this));

            // Execute the swap.
            uint256 tokenOutAmountOut = uniswapV3Router.exactInput(
                IUniswapV3Router.ExactInputParams({
                    path: encodePackedPath,
                    recipient: address(this),
                    deadline: block.timestamp + 60,
                    amountIn: amount,
                    amountOutMinimum: amountOutMin
                })
            );

            uint256 tokenInAmountIn = tokenInBalance - tokenIn.balanceOf(address(this));

            uint256 tokenInValueOut = priceRouter.getValue(tokenOut, tokenOutAmountOut, tokenIn);

            if (tokenInValueOut < tokenInAmountIn.mulDivDown(slippage(), 1e4)) revert BaseAdaptor__Slippage();
        } else {
            // Token In is not supported by price router, so we know it is at least not the Cellars Reserves,
            // or a prominent asset, so skip value in vs value out check.
            // Execute the swap.
            uniswapV3Router.exactInput(
                IUniswapV3Router.ExactInputParams({
                    path: encodePackedPath,
                    recipient: address(this),
                    deadline: block.timestamp + 60,
                    amountIn: amount,
                    amountOutMinimum: amountOutMin
                })
            );
        }

        // Insure spender has zero approval.
        _revokeExternalApproval(tokenIn, address(uniswapV3Router));
    }
}
