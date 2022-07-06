// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Multicall } from "src/base/Multicall.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { Multicall } from "src/base/Multicall.sol";

/**
 * @title Sommelier Price Router
 * @notice Provides a universal interface allowing Sommelier contracts to interact with multiple
 *         different exchanges to perform swaps.
 * @dev Perform multiple swaps using Multicall.
 * @author crispymangoes, Brian Le
 */
contract SwapRouter is Multicall {
    using SafeTransferLib for ERC20;

    /** @notice Planned additions
        BALANCERV2,
        CURVE,
        ONEINCH
    */
    enum Exchange {
        UNIV2,
        UNIV3
    }

    mapping(Exchange => bytes4) public getExchangeSelector;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Uniswap V2 swap router contract. Used for swapping if pool fees are not specified.
     */
    IUniswapV2Router public immutable uniswapV2Router; // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D

    /**
     * @notice Uniswap V3 swap router contract. Used for swapping if pool fees are specified.
     */
    IUniswapV3Router public immutable uniswapV3Router; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    /**
     *
     */
    constructor(IUniswapV2Router _uniswapV2Router, IUniswapV3Router _uniswapV3Router) {
        // Set up all exchanges.
        uniswapV2Router = _uniswapV2Router;
        uniswapV3Router = _uniswapV3Router;

        // Set up mapping between IDs and selectors.
        getExchangeSelector[Exchange.UNIV2] = SwapRouter(this).swapWithUniV2.selector;
        getExchangeSelector[Exchange.UNIV3] = SwapRouter(this).swapWithUniV3.selector;
    }

    // ======================================= SWAP OPERATIONS =======================================
    /**
     * @notice Route swap calls to the appropriate exchanges.
     * @param exchange value dictating which exchange to use to make the swap
     * @param swapData encoded data used for the swap
     * @param recipient address to send the swapped tokens to
     * @return amountOut amount of tokens received from the swap
     */
    function swap(
        Exchange exchange,
        bytes memory swapData,
        address recipient
    ) external returns (uint256 amountOut) {
        // Route swap call to appropriate function using selector.
        (bool success, bytes memory result) = address(this).delegatecall(
            abi.encodeWithSelector(getExchangeSelector[exchange], swapData, recipient)
        );

        if (!success) {
            // If there is return data, the call reverted with a reason or a custom error so we
            // bubble up the error message.
            if (result.length > 0) {
                assembly {
                    let returndata_size := mload(result)
                    revert(add(32, result), returndata_size)
                }
            } else {
                revert("Swap reverted.");
            }
        }

        amountOut = abi.decode(result, (uint256));
    }

    /**
     * @notice Allows caller to make swaps using the UniswapV2 Exchange.
     * @param swapData bytes variable storing the following swap information:
     *      address[] path: array of addresses dictating what swap path to follow
     *      uint256 assets: the amount of path[0] you want to swap with
     *      uint256 assetsOutMin: the minimum amount of path[path.length - 1] tokens you want from the swap
     * @param recipient address to send the swapped tokens to
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithUniV2(bytes memory swapData, address recipient) public returns (uint256 amountOut) {
        (address[] memory path, uint256 assets, uint256 assetsOutMin) = abi.decode(
            swapData,
            (address[], uint256, uint256)
        );

        // Transfer assets to this contract to swap.
        ERC20 assetIn = ERC20(path[0]);
        assetIn.safeTransferFrom(msg.sender, address(this), assets);

        // Approve assets to be swapped through the router.
        assetIn.safeApprove(address(uniswapV2Router), assets);

        // Execute the swap.
        uint256[] memory amountsOut = uniswapV2Router.swapExactTokensForTokens(
            assets,
            assetsOutMin,
            path,
            recipient,
            block.timestamp + 60
        );

        amountOut = amountsOut[amountsOut.length - 1];
    }

    /**
     * @notice Allows caller to make swaps using the UniswapV3 Exchange.
     * @param swapData bytes variable storing the following swap information
     *      address[] path: array of addresses dictating what swap path to follow
     *      uint24[] poolFees: array of pool fees dictating what swap pools to use
     *      uint256 assets: the amount of path[0] you want to swap with
     *      uint256 assetsOutMin: the minimum amount of path[path.length - 1] tokens you want from the swap
     * @param recipient address to send the swapped tokens to
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithUniV3(bytes memory swapData, address recipient) public returns (uint256 amountOut) {
        (address[] memory path, uint24[] memory poolFees, uint256 assets, uint256 assetsOutMin) = abi.decode(
            swapData,
            (address[], uint24[], uint256, uint256)
        );

        // Transfer assets to this contract to swap.
        ERC20 assetIn = ERC20(path[0]);
        assetIn.safeTransferFrom(msg.sender, address(this), assets);

        // Approve assets to be swapped through the router.
        assetIn.safeApprove(address(uniswapV3Router), assets);

        // Encode swap parameters.
        bytes memory encodePackedPath = abi.encodePacked(address(assetIn));
        for (uint256 i = 1; i < path.length; i++)
            encodePackedPath = abi.encodePacked(encodePackedPath, poolFees[i - 1], path[i]);

        // Execute the swap.
        amountOut = uniswapV3Router.exactInput(
            IUniswapV3Router.ExactInputParams({
                path: encodePackedPath,
                recipient: recipient,
                deadline: block.timestamp + 60,
                amountIn: assets,
                amountOutMinimum: assetsOutMin
            })
        );
    }
}
