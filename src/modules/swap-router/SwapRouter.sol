// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { ICurveSwaps } from "src/interfaces/ICurveSwaps.sol";
import { IBalancerExchangeProxy, TokenInterface } from "src/interfaces/BalancerInterfaces.sol";

contract SwapRouter {
    using SafeTransferLib for ERC20;

    /** @notice Planned additions
        BALANCERV2,
        CURVE,
        ONEINCH
    */
    enum Exchange {
        UNIV2,
        UNIV3,
        CURVE,
        BALANCERV2
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
     * @notice Curve Registry Exchange contract. Used for rebalancing positions.
     */
    ICurveSwaps public immutable curveRegistryExchange; // 0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7

    /**
     * @notice Balancer ExchangeProxy V2 contract.
     */
    IBalancerExchangeProxy public immutable balancerExchangeProxy; // 0x3E66B66Fd1d0b02fDa6C811Da9E0547970DB2f21

    /**
     * @param _uniswapV2Router Uniswap V2 swap router address
     * @param _uniswapV3Router Uniswap V3 swap router address
     * @param _curveRegistryExchange Curve registry exchange
     * @param _balancerExchangeProxy Balancer ExchangeProxy V2
     */
    constructor(
        IUniswapV2Router _uniswapV2Router,
        IUniswapV3Router _uniswapV3Router,
        ICurveSwaps _curveRegistryExchange,
        IBalancerExchangeProxy _balancerExchangeProxy
    )
    {
        //set up all exchanges
        uniswapV2Router = _uniswapV2Router;
        uniswapV3Router = _uniswapV3Router;
        curveRegistryExchange = _curveRegistryExchange;
        balancerExchangeProxy = _balancerExchangeProxy;

        //set up mapping between ids and selectors
        getExchangeSelector[Exchange.UNIV2] = SwapRouter(this).swapWithUniV2.selector;
        getExchangeSelector[Exchange.UNIV3] = SwapRouter(this).swapWithUniV3.selector;
        getExchangeSelector[Exchange.CURVE] = SwapRouter(this).swapWithCurve.selector;
        getExchangeSelector[Exchange.BALANCERV2] = SwapRouter(this).swapWithBalancerV2.selector;
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
        (bool success, bytes memory result) = address(this).call(
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
     *      address recipient: the address path[path.length - 1] token should be sent to
     *      address from: the address to transfer path[0] tokens from to this address.
     * @param recipient address to send the swapped tokens to
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithUniV2(bytes memory swapData, address recipient) public returns (uint256 amountOut) {
        (address[] memory path, uint256 assets, uint256 assetsOutMin, address from) = abi.decode(
            swapData,
            (address[], uint256, uint256, address)
        );

        // Transfer assets to this contract to swap.
        ERC20 assetIn = ERC20(path[0]);
        assetIn.safeTransferFrom(from, address(this), assets);

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
     *      uint24[] memory poolFees: array of pool fees dictating what swap pools to use
     *      uint256 assets: the amount of path[0] you want to swap with
     *      uint256 assetsOutMin: the minimum amount of path[path.length - 1] tokens you want from the swap
     *      address recipient: the address path[path.length - 1] token should be sent to
     *      address from: the address to transfer path[0] tokens from to this address.
     * @param recipient address to send the swapped tokens to
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithUniV3(bytes memory swapData, address recipient) public returns (uint256 amountOut) {
        (address[] memory path, uint24[] memory poolFees, uint256 assets, uint256 assetsOutMin, address from) = abi
            .decode(swapData, (address[], uint24[], uint256, uint256, address));

        // Transfer assets to this contract to swap.
        ERC20 assetIn = ERC20(path[0]);
        assetIn.safeTransferFrom(from, address(this), assets);

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
            ERC20 assetOut: the asset being received
            uint256 assets: the amount of assetIn you want to swap with
     *      uint256 assetsOutMin: the minimum amount of assetOut tokens you want from the swap
     *      address from: the address to transfer assetIn tokens from to this address
     *      address recipient: the address assetOut token should be sent to.
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithCurve(bytes memory swapData) public returns (uint256 amountOut) {
        (
            address[9] memory route,
            uint256[3][4] memory swapParams,
            ERC20 assetIn,
            ERC20 assetOut,
            uint256 assets,
            uint256 assetsOutMin,
            address from,
            address recipient
        ) = abi.decode(swapData, (address[9], uint256[3][4], ERC20, ERC20, uint256, uint256, address, address));

        // Transfer assets to this contract to swap.
        assetIn.safeTransferFrom(from, address(this), assets);

        // Execute the stablecoin swap.
        assetIn.safeApprove(address(curveRegistryExchange), assets);
        amountOut = curveRegistryExchange.exchange_multiple(
            route,
            swapParams,
            assets,
            assetsOutMin
        );

        // Transfer the amountOut of assetOut tokens from the router to the recipient.
        assetOut.safeTransfer(recipient, amountOut);
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
     *      address recipient: the address assetOut token should be sent to.
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithBalancerV2(bytes memory swapData) public returns (uint256 amountOut) {
        (
            address pool,
            ERC20 assetIn,
            ERC20 assetOut,
            uint256 assets,
            uint256 assetsOutMin,
            address from,
            address recipient
        ) = abi.decode(swapData, (address, ERC20, ERC20, uint256, uint256, address, address));

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

        // Transfer the amountOut of assetOut tokens from the router to the recipient.
        assetOut.safeTransfer(recipient, amountOut);
    }
}
