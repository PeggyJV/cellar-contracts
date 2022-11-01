// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Multicall } from "src/base/Multicall.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { IAggregationRouterV4, SwapDescription } from "src/interfaces/external/IAggregationRouterV4.sol";
import { IAggregationExecutor } from "src/interfaces/external/IAggregationExecutor.sol";
import { console } from "@forge-std/Test.sol";

/**
 * @title Sommelier Swap Router
 * @notice Provides a universal interface allowing Sommelier contracts to interact with multiple
 *         different exchanges to perform swaps.
 * @dev Perform multiple swaps using Multicall.
 * @author crispymangoes, Brian Le
 */
contract SwapRouter is Multicall {
    using SafeERC20 for ERC20;

    /**
     * @param BASIC Uniswap V2, or Uniswap V3
     * @param Aggregator 0x
     */
    enum Exchange {
        BASIC,
        AGGREGATOR
    }

    /**
     * @notice Get the selector of the function to call in order to perform swap with a given exchange.
     */
    mapping(Exchange => bytes4) public getExchangeSelector;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Uniswap V2 swap router contract.
     */
    IUniswapV2Router public immutable uniswapV2Router; // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D

    /**
     * @notice Uniswap V3 swap router contract.
     */
    IUniswapV3Router public immutable uniswapV3Router; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    // IAggregationRouterV4 public immutable oneInchRouter; // 0x1111111254fb6c44bAC0beD2854e76F90643097d

    address public immutable zeroXExchangeProxy;

    //TODO does this change?

    /**
     * @param _uniswapV2Router address of the Uniswap V2 swap router contract
     * @param _uniswapV3Router address of the Uniswap V3 swap router contract
     */
    constructor(
        IUniswapV2Router _uniswapV2Router,
        IUniswapV3Router _uniswapV3Router,
        address _zeroXExchangeProxy
    ) {
        // Set up all exchanges.
        uniswapV2Router = _uniswapV2Router;
        uniswapV3Router = _uniswapV3Router;
        zeroXExchangeProxy = _zeroXExchangeProxy;

        // Set up mapping between IDs and selectors.
        getExchangeSelector[Exchange.BASIC] = SwapRouter(this).swapWithUniswap.selector;
        getExchangeSelector[Exchange.AGGREGATOR] = SwapRouter(this).swapWith0x.selector;
    }

    // ======================================= SWAP OPERATIONS =======================================

    /**
     * @notice Attempted to perform a swap that reverted without a message.
     */
    error SwapRouter__SwapReverted();

    /**
     * @notice Attempted to perform a swap with mismatched assetIn and swap data.
     * @param actual the address encoded into the swap data
     * @param expected the address passed in with assetIn
     */
    error SwapRouter__AssetInMisMatch(address actual, address expected);

    /**
     * @notice Attempted to perform a swap with mismatched assetOut and swap data.
     * @param actual the address encoded into the swap data
     * @param expected the address passed in with assetIn
     */
    error SwapRouter__AssetOutMisMatch(address actual, address expected);

    /**
     * @notice Perform a swap using a supported exchange.
     * @param exchange value dictating which exchange to use to make the swap
     * @param swapData encoded data used for the swap
     * @param receiver address to send the received assets to
     * @return amountOut amount of assets received from the swap
     */
    function swap(
        Exchange exchange,
        bytes memory swapData,
        address receiver,
        ERC20 assetIn,
        ERC20 assetOut
    ) external returns (uint256 amountOut) {
        // Route swap call to appropriate function using selector.
        (bool success, bytes memory result) = address(this).delegatecall(
            abi.encodeWithSelector(getExchangeSelector[exchange], swapData, receiver, assetIn, assetOut)
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
                revert SwapRouter__SwapReverted();
            }
        }

        amountOut = abi.decode(result, (uint256));
    }

    /**
     * @notice Perform a basic swap using Uniswap V2/V3.
     * @param swapData bytes variable storing the following swap information
     *      uint8 swapType: 0 for V2, 1 for V3.
     *      address[] path: array of addresses dictating what swap path to follow
     *      uint24[] poolFees(if swapType == 1): array of pool fees dictating what swap pools to use
     *      uint256 amount: amount of the first asset in the path to swap
     *      uint256 amountOutMin: the minimum amount of the last asset in the path to receive
     * @param receiver address to send the received assets to
     * @return amountOut amount of assets received from the swap
     */
    //TODO doing it this way with the swapType being the first value breaks compatibility with the router...
    function swapWithUniswap(
        bytes memory swapData,
        address receiver,
        ERC20 assetIn,
        ERC20 assetOut
    ) public returns (uint256 amountOut) {
        // bool swapType;
        address[] memory path;
        uint256 amount;
        uint256 amountOutMin;
        uint24[] memory poolFees;
        uint8 swapType = abi.decode(swapData, (uint8));
        if (swapType == 0) {
            (, path, amount, amountOutMin) = abi.decode(swapData, (uint8, address[], uint256, uint256));
        } else {
            (, path, poolFees, amount, amountOutMin) = abi.decode(
                swapData,
                (uint8, address[], uint24[], uint256, uint256)
            );
        }

        // Check that path matches assetIn and assetOut.
        if (assetIn != ERC20(path[0])) revert SwapRouter__AssetInMisMatch(path[0], address(assetIn));
        if (assetOut != ERC20(path[path.length - 1]))
            revert SwapRouter__AssetOutMisMatch(path[path.length - 1], address(assetOut));

        // Transfer assets to this contract to swap.
        assetIn.safeTransferFrom(msg.sender, address(this), amount);

        if (swapType == 0) {
            // Approve assets to be swapped through the router.
            assetIn.safeApprove(address(uniswapV2Router), amount);

            // Execute the swap.
            uint256[] memory amountsOut = uniswapV2Router.swapExactTokensForTokens(
                amount,
                amountOutMin,
                path,
                receiver,
                block.timestamp + 60
            );

            amountOut = amountsOut[amountsOut.length - 1];

            _checkApprovalIsZero(assetIn, address(uniswapV2Router));
        } else if (swapType == 1) {
            // Approve assets to be swapped through the router.
            assetIn.safeApprove(address(uniswapV3Router), amount);

            // Encode swap parameters.
            bytes memory encodePackedPath = abi.encodePacked(address(assetIn));
            for (uint256 i = 1; i < path.length; i++)
                encodePackedPath = abi.encodePacked(encodePackedPath, poolFees[i - 1], path[i]);

            // Execute the swap.
            amountOut = uniswapV3Router.exactInput(
                IUniswapV3Router.ExactInputParams({
                    path: encodePackedPath,
                    recipient: receiver,
                    deadline: block.timestamp + 60,
                    amountIn: amount,
                    amountOutMinimum: amountOutMin
                })
            );

            _checkApprovalIsZero(assetIn, address(uniswapV3Router));
        }
    }

    /**
     * @notice Emitted when a 0x swap call fails.
     */
    error SwapRouter__0xCallFailed();

    /**
     * @notice Attempted to make swap call to the wrong address.
     */
    error SwapRouter__0xCallBadTarget();

    /**
     * @notice Perform a swap using 0x.
     * @param swapData bytes variable storing the following swap information
     *      uint256 amount: amount of the first asset in the path to swap
     *      address spender: address spending assetIn
     *      address swapTarget: address swapCallData is made on
     *      bytes swapCallData: call data to perform arbritrary 0x actions.
     * @param receiver address to send the received assets to
     * @return amountOut amount of assets received from the swap
     */
    function swapWith0x(
        bytes memory swapData,
        address receiver,
        ERC20 assetIn,
        ERC20 assetOut
    ) public returns (uint256 amountOut) {
        (uint256 amount, address spender, address payable swapTarget, bytes memory swapCallData) = abi.decode(
            swapData,
            (uint256, address, address, bytes)
        );

        if (spender != zeroXExchangeProxy || swapTarget != zeroXExchangeProxy) revert SwapRouter__0xCallBadTarget();

        // Transfer assets to this contract to swap.
        assetIn.safeTransferFrom(msg.sender, address(this), amount);
        // Approve assets to be swapped through the router.
        assetIn.safeApprove(spender, amount);

        // Record assetOut starting balance and make the swap.
        amountOut = assetOut.balanceOf(address(this));
        (bool success, ) = swapTarget.call(swapCallData);
        if (!success) revert SwapRouter__0xCallFailed();

        // Make sure swap used all the approval, and send bought tokens to caller.
        _checkApprovalIsZero(assetIn, zeroXExchangeProxy);
        amountOut = assetOut.balanceOf(address(this)) - amountOut;
        assetOut.safeTransfer(receiver, amountOut);
    }

    /**
     * @notice Emitted when a swap does not use all the assets swap router approved.
     */
    error SwapRouter__UnusedApproval();

    /**
     * @notice Helper function that reverts if the Swap Router has unused approval after a swap is made.
     */
    function _checkApprovalIsZero(ERC20 asset, address spender) internal view {
        if (asset.allowance(address(this), spender) != 0) revert SwapRouter__UnusedApproval();
    }
}
