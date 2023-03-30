// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { PositionlessAdaptor } from "src/modules/adaptors/PositionlessAdaptor.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";

/**
 * @title Swap with Uniswap Adaptor
 * @notice Allows Cellars to swap with 0x.
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

    error SwapWithUniswapAdaptor__AssetInMisMatch(address actual, address expected);
    error SwapWithUniswapAdaptor__AssetOutMisMatch(address actual, address expected);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("0x Adaptor V 1.0"));
    }

    /**
     * @notice Address of the current 0x swap target on Mainnet ETH.
     */
    function target() public pure virtual returns (address) {
        return 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    }

    function uniswapV2Router() public pure virtual returns (address) {
        return 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    }

    function uniswapV3Router() public pure virtual returns (address) {
        return 0xE592427A0AEce92De3Edee1F18E0157C05861564;
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
            if (!priceRouter.isSupported(tokenOut)) revert BaseAdaptor__PricingNotSupported(address(tokenOut));
            // Save token balances.
            uint256 tokenInBalance = tokenIn.balanceOf(address(this));
            uint256 tokenOutBalance = tokenOut.balanceOf(address(this));

            // Perform Swap.
            target().functionCall(swapCallData);

            uint256 tokenInAmountIn = tokenInBalance - tokenIn.balanceOf(address(this));
            uint256 tokenOutAmountOut = tokenOut.balanceOf(address(this)) - tokenOutBalance;

            uint256 tokenInValueOut = priceRouter.getValue(tokenOut, tokenOutAmountOut, tokenIn);

            if (tokenInValueOut < tokenInAmountIn.mulDivDown(slippage(), 1e4)) revert BaseAdaptor__Slippage();
        } else {
            // Token In is not supported by price router, so we know it is at least not the Cellars Reserves,
            // or a prominent asset, so skip value in vs value out check.
            target().functionCall(swapCallData);
        }

        // Insure spender has zero approval.
        _revokeExternalApproval(tokenIn, target());
    }

    // /**
    //  * @notice Perform a swap using Uniswap V2.
    //  * @param swapData bytes variable storing the following swap information:
    //  *      address[] path: array of addresses dictating what swap path to follow
    //  *      uint256 amount: amount of the first asset in the path to swap
    //  *      uint256 amountOutMin: the minimum amount of the last asset in the path to receive
    //  * @param receiver address to send the received assets to
    //  * @return amountOut amount of assets received from the swap
    //  */
    // function swapWithUniV2(
    //     bytes memory swapData,
    //     address receiver,
    //     ERC20 assetIn,
    //     ERC20 assetOut
    // ) public returns (uint256 amountOut) {
    //     (address[] memory path, uint256 amount, uint256 amountOutMin) = abi.decode(
    //         swapData,
    //         (address[], uint256, uint256)
    //     );

    //     // Check that path matches assetIn and assetOut.
    //     if (assetIn != ERC20(path[0])) revert SwapWithUniswapAdaptor__AssetInMisMatch(path[0], address(assetIn));
    //     if (assetOut != ERC20(path[path.length - 1]))
    //         revert SwapWithUniswapAdaptor__AssetOutMisMatch(path[path.length - 1], address(assetOut));

    //     // Transfer assets to this contract to swap.
    //     assetIn.safeTransferFrom(msg.sender, address(this), amount);

    //     // Approve assets to be swapped through the router.
    //     assetIn.safeApprove(address(uniswapV2Router), amount);

    //     // Execute the swap.
    //     uint256[] memory amountsOut = uniswapV2Router.swapExactTokensForTokens(
    //         amount,
    //         amountOutMin,
    //         path,
    //         receiver,
    //         block.timestamp + 60
    //     );

    //     amountOut = amountsOut[amountsOut.length - 1];

    //     _checkApprovalIsZero(assetIn, address(uniswapV2Router));
    // }

    // function swapWithUniV3(
    //     bytes memory swapData,
    //     address receiver,
    //     ERC20 assetIn,
    //     ERC20 assetOut
    // ) public returns (uint256 amountOut) {
    //     (address[] memory path, uint24[] memory poolFees, uint256 amount, uint256 amountOutMin) = abi.decode(
    //         swapData,
    //         (address[], uint24[], uint256, uint256)
    //     );

    //     // Check that path matches assetIn and assetOut.
    //     if (assetIn != ERC20(path[0])) revert SwapRouter__AssetInMisMatch(path[0], address(assetIn));
    //     if (assetOut != ERC20(path[path.length - 1]))
    //         revert SwapRouter__AssetOutMisMatch(path[path.length - 1], address(assetOut));

    //     // Transfer assets to this contract to swap.
    //     assetIn.safeTransferFrom(msg.sender, address(this), amount);

    //     // Approve assets to be swapped through the router.
    //     assetIn.safeApprove(address(uniswapV3Router), amount);

    //     // Encode swap parameters.
    //     bytes memory encodePackedPath = abi.encodePacked(address(assetIn));
    //     for (uint256 i = 1; i < path.length; i++)
    //         encodePackedPath = abi.encodePacked(encodePackedPath, poolFees[i - 1], path[i]);

    //     // Execute the swap.
    //     amountOut = uniswapV3Router.exactInput(
    //         IUniswapV3Router.ExactInputParams({
    //             path: encodePackedPath,
    //             recipient: receiver,
    //             deadline: block.timestamp + 60,
    //             amountIn: amount,
    //             amountOutMinimum: amountOutMin
    //         })
    //     );

    //     _checkApprovalIsZero(assetIn, address(uniswapV3Router));
    // }
}
