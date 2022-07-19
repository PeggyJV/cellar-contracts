// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Multicall } from "src/base/Multicall.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { ICurveSwaps } from "src/interfaces/ICurveSwaps.sol";
import { IBalancerExchangeProxy, TokenInterface } from "src/interfaces/BalancerInterfaces.sol";
import { Multicall } from "src/base/Multicall.sol";

/**
 * @title Sommelier Swap Router
 * @notice Provides a universal interface allowing Sommelier contracts to interact with multiple
 *         different exchanges to perform swaps.
 * @dev Perform multiple swaps using Multicall.
 * @author crispymangoes, Brian Le
 */
contract SwapRouter is Multicall {
    using SafeTransferLib for ERC20;

    /** @notice Planned additions
        ONEINCH
    */

    /**
     * @param UNIV2 Uniswap V2
     * @param UNIV3 Uniswap V3
     * @param CURVE Curve Exchange
     * @param BALANCERV2 Balancer V2
     */
    enum Exchange {
        UNIV2,
        UNIV3,
        CURVE,
        BALANCERV2
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

    /**
     * @notice Curve registry exchange contract.
     */
    ICurveSwaps public immutable curveRegistryExchange; // 0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7

    /**
     * @notice Balancer ExchangeProxy V2 contract.
     */
    IBalancerExchangeProxy public immutable balancerExchangeProxy; // 0x3E66B66Fd1d0b02fDa6C811Da9E0547970DB2f21

    /**
     * @param _uniswapV2Router address of the Uniswap V2 swap router contract
     * @param _uniswapV3Router address of the Uniswap V3 swap router contract
     * @param _curveRegistryExchange address of the Curve registry exchange contract
     * @param _balancerExchangeProxy address of the Balancer ExchangeProxy V2 contract
     */
    constructor(
        IUniswapV2Router _uniswapV2Router,
        IUniswapV3Router _uniswapV3Router,
        ICurveSwaps _curveRegistryExchange,
        IBalancerExchangeProxy _balancerExchangeProxy
    )
    {
        // Set up all exchanges.
        uniswapV2Router = _uniswapV2Router;
        uniswapV3Router = _uniswapV3Router;
        curveRegistryExchange = _curveRegistryExchange;
        balancerExchangeProxy = _balancerExchangeProxy;

        // Set up mapping between IDs and selectors.
        getExchangeSelector[Exchange.UNIV2] = SwapRouter(this).swapWithUniV2.selector;
        getExchangeSelector[Exchange.UNIV3] = SwapRouter(this).swapWithUniV3.selector;
        getExchangeSelector[Exchange.CURVE] = SwapRouter(this).swapWithCurve.selector;
        getExchangeSelector[Exchange.BALANCERV2] = SwapRouter(this).swapWithBalancerV2.selector;
    }

    // ======================================= SWAP OPERATIONS =======================================
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
        address receiver
    ) external returns (uint256 amountOut) {
        // Route swap call to appropriate function using selector.
        (bool success, bytes memory result) = address(this).delegatecall(
            abi.encodeWithSelector(getExchangeSelector[exchange], swapData, receiver)
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
     * @notice Perform a swap using Uniswap V2.
     * @param swapData bytes variable storing the following swap information:
     *      address[] path: array of addresses dictating what swap path to follow
     *      uint256 amount: amount of the first asset in the path to swap
     *      uint256 amountOutMin: the minimum amount of the last asset in the path to receive
     * @param receiver address to send the received assets to
     * @return amountOut amount of assets received from the swap
     */
    function swapWithUniV2(bytes memory swapData, address receiver) public returns (uint256 amountOut) {
        (address[] memory path, uint256 amount, uint256 amountOutMin) = abi.decode(
            swapData,
            (address[], uint256, uint256)
        );

        // Transfer assets to this contract to swap.
        ERC20 assetIn = ERC20(path[0]);
        assetIn.safeTransferFrom(msg.sender, address(this), amount);

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
    }

    /**
     * @notice Perform a swap using Uniswap V3.
     * @param swapData bytes variable storing the following swap information
     *      address[] path: array of addresses dictating what swap path to follow
     *      uint24[] poolFees: array of pool fees dictating what swap pools to use
     *      uint256 amount: amount of the first asset in the path to swap
     *      uint256 amountOutMin: the minimum amount of the last asset in the path to receive
     * @param receiver address to send the received assets to
     * @return amountOut amount of assets received from the swap
     */
    function swapWithUniV3(bytes memory swapData, address receiver) public returns (uint256 amountOut) {
        (address[] memory path, uint24[] memory poolFees, uint256 amount, uint256 amountOutMin) = abi.decode(
            swapData,
            (address[], uint24[], uint256, uint256)
        );

        // Transfer assets to this contract to swap.
        ERC20 assetIn = ERC20(path[0]);
        assetIn.safeTransferFrom(msg.sender, address(this), amount);

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
    }

    /**
     * @notice Allows caller to make swaps using the Curve Exchange.
     * @param swapData bytes variable storing the following swap information
     *      address[9] route: array of [initial token, pool, token, pool, token, ...] that specifies the swap route on Curve.
     *      uint256[3][4] swapParams: multidimensional array of [i, j, swap type]
     *          where i and j are the correct values for the n'th pool in `_route` and swap type should be
     *              1 for a stableswap `exchange`,
     *              2 for stableswap `exchange_underlying`,
     *              3 for a cryptoswap `exchange`,
     *              4 for a cryptoswap `exchange_underlying`
            ERC20 assetIn: the asset being swapped
            uint256 assets: the amount of assetIn you want to swap with
     *      uint256 assetsOutMin: the minimum amount of assetOut tokens you want from the swap
     *      address from: the address to transfer assetIn tokens from to this address
     * @param receiver the address assetOut token should be sent to
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithCurve(bytes memory swapData, address receiver) public returns (uint256 amountOut) {
        (
            address[9] memory route,
            uint256[3][4] memory swapParams,
            ERC20 assetIn,
            uint256 assets,
            uint256 assetsOutMin,
            address from
        ) = abi.decode(swapData, (address[9], uint256[3][4], ERC20, uint256, uint256, address));

        // Transfer assets to this contract to swap.
        assetIn.safeTransferFrom(from, address(this), assets);

        address[4] memory pools;

        // Execute the stablecoin swap.
        assetIn.safeApprove(address(curveRegistryExchange), assets);
        amountOut = curveRegistryExchange.exchange_multiple(
            route,
            swapParams,
            assets,
            assetsOutMin,
            pools,
            receiver
        );
    }

    /**
     * @notice Allows caller to make swaps using Balancer V2.
     * @param swapData bytes variable storing the following swap information
     *      address pool: 
            ERC20 assetIn: the asset being swapped
            ERC20 assetOut: the asset being received
            uint256 assets: the amount of assetIn you want to swap with
     *      uint256 assetsOutMin: the minimum amount of assetOut tokens you want from the swap
     *      address from: the address to transfer assetIn tokens from to this address
     * @param receiver the address assetOut token should be sent to
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithBalancerV2(bytes memory swapData, address receiver) public returns (uint256 amountOut) {
        (
            address pool,
            ERC20 assetIn,
            ERC20 assetOut,
            uint256 assets,
            uint256 assetsOutMin,
            address from
        ) = abi.decode(swapData, (address, ERC20, ERC20, uint256, uint256, address));

        // Transfer assets to this contract to swap.
        assetIn.safeTransferFrom(from, address(this), assets);

        // Execute the multihop swap.
        assetIn.safeApprove(address(balancerExchangeProxy), assets);

        IBalancerExchangeProxy.Swap[][] memory swapSequences = new IBalancerExchangeProxy.Swap[][](1);
        swapSequences[0] = new IBalancerExchangeProxy.Swap[](1);

        swapSequences[0][0].pool = pool;
        swapSequences[0][0].tokenIn = address(assetIn);
        swapSequences[0][0].tokenOut = address(assetOut);
        swapSequences[0][0].swapAmount = assets;
        swapSequences[0][0].maxPrice = type(uint256).max;

        amountOut = balancerExchangeProxy.multihopBatchSwapExactIn(
            swapSequences,
            TokenInterface(address(assetIn)),
            TokenInterface(address(assetOut)),
            assets,
            assetsOutMin
        );

        // Transfer the amountOut of assetOut tokens from the router to the receiver.
        assetOut.safeTransfer(receiver, amountOut);
    }
}
