// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Cellar } from "./base/Cellar.sol";
import { IUniswapV3Router } from "./interfaces/IUniswapV3Router.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "./interfaces/IUniswapV2Router02.sol";
import { ICellarRouter } from "./interfaces/ICellarRouter.sol";
import { Registry } from "src/Registry.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";

import "./Errors.sol";

contract CellarRouter is ICellarRouter {
    using SafeTransferLib for ERC20;

    // ========================================== CONSTRUCTOR ==========================================
    /**
     * @notice Uniswap V3 swap router contract. Used for swapping if pool fees are specified.
     */
    IUniswapV3Router public immutable uniswapV3Router; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    /**
     * @notice Uniswap V2 swap router contract. Used for swapping if pool fees are not specified.
     */
    IUniswapV2Router public immutable uniswapV2Router; // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D

    /**
     * @notice Registry contract
     */
    Registry public immutable registry; //TODO set registry

    /**
     * @param _uniswapV3Router Uniswap V3 swap router address
     * @param _uniswapV2Router Uniswap V2 swap router address
     */
    constructor(
        IUniswapV3Router _uniswapV3Router,
        IUniswapV2Router _uniswapV2Router,
        Registry _registry
    ) {
        uniswapV3Router = _uniswapV3Router;
        uniswapV2Router = _uniswapV2Router;
        registry = _registry;
    }

    // ======================================= DEPOSIT OPERATIONS =======================================

    /**
     * @notice Deposit assets into a cellar using permit.
     * @param cellar address of the cellar to deposit into
     * @param assets amount of assets to deposit
     * @param receiver address receiving the shares
     * @param deadline timestamp after which permit is invalid
     * @param signature a valid secp256k1 signature
     * @return shares amount of shares minted
     */
    function depositIntoCellarWithPermit(
        Cellar cellar,
        uint256 assets,
        address receiver,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares) {
        // Retrieve the cellar's current asset.
        ERC20 asset = cellar.asset();

        // Approve the assets from the user to the router via permit.
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        asset.permit(msg.sender, address(this), assets, deadline, v, r, s);

        // Transfer assets from the user to the router.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // Approve the cellar to spend assets.
        asset.safeApprove(address(cellar), assets);

        // Deposit assets into the cellar.
        shares = cellar.deposit(assets, receiver);
    }

    /**
     * @notice Deposit into a cellar by first performing a swap to the cellar's current asset if necessary.
     * @dev If using Uniswap V3 for swap, must specify the pool fee tier to use for each swap. For
     *      example, if there are "n" addresses in path, there should be "n-1" values specifying the
     *      fee tiers of each pool used for each swap. The current possible pool fee tiers for
     *      Uniswap V3 are 0.01% (100), 0.05% (500), 0.3% (3000), and 1% (10000). If using Uniswap
     *      V2, leave pool fees empty to use Uniswap V2 for swap.
     * @param cellar address of the cellar
     * @param exchange ENUM representing what exchange to make the swap at
     *        Refer to src/SwapRouter.sol for list of available options
     * @param swapData bytes variable containing all the data needed to make a swap
     * @param assets amount of assets to deposit
     * @param receiver address to recieve the cellar shares
     * @param assetIn ERC20 asset caller wants to swap and deposit with
     * @return shares amount of shares minted
     */
    function depositAndSwapIntoCellar(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        address receiver,
        ERC20 assetIn
    ) public returns (uint256 shares) {
        // Retrieve the asset being swapped and asset of cellar.
        ERC20 asset = cellar.asset();

        // Transfer assets from the user to the router.
        assetIn.safeTransferFrom(msg.sender, address(this), assets);

        // Swap assets into desired token
        assetIn.safeApprove(address(registry.swapRouter()), assets);
        assets = registry.swapRouter().swap(exchange, swapData);

        // Approve the cellar to spend assets.
        asset.safeApprove(address(cellar), assets);

        // Deposit assets into the cellar.
        shares = cellar.deposit(assets, receiver);
    }

    /**
     * @notice Deposit into a cellar by first performing a swap to the cellar's current asset if necessary.
     * @dev If using Uniswap V3 for swap, must specify the pool fee tier to use for each swap. For
     *      example, if there are "n" addresses in path, there should be "n-1" values specifying the
     *      fee tiers of each pool used for each swap. The current possible pool fee tiers for
     *      Uniswap V3 are 0.01% (100), 0.05% (500), 0.3% (3000), and 1% (10000). If using Uniswap
     *      V2, leave pool fees empty to use Uniswap V2 for swap.
     * @param cellar address of the cellar to deposit into
     * @param exchange ENUM representing what exchange to make the swap at
     *        Refer to src/SwapRouter.sol for list of available options
     * @param swapData bytes variable containing all the data needed to make a swap
     * @param assets amount of assets to deposit
     * @param assetIn ERC20 asset caller wants to swap and deposit with
     * @param reciever address to recieve the cellar shares
     * @param deadline timestamp after which permit is invalid
     * @param signature a valid secp256k1 signature
     * @return shares amount of shares minted
     */
    function depositAndSwapIntoCellarWithPermit(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        ERC20 assetIn,
        address reciever,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares) {
        // Approve for router to burn user shares via permit.
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        assetIn.permit(msg.sender, address(this), assets, deadline, v, r, s);

        // Deposit assets into the cellar using a swap if necessary.
        shares = depositAndSwapIntoCellar(cellar, exchange, swapData, assets, reciever, assetIn);
    }

    // ======================================= WITHDRAW OPERATIONS =======================================

    /**
     * @notice Withdraws from a cellar and then performs a swap to another desired asset, if the
     *         withdrawn asset is not already.
     * @dev Permission is required from caller for router to burn shares. Please make sure that
     *      caller has approved the router to spend their shares.
     * @param cellar address of the cellar
     * @param exchange ENUM representing what exchange to make the swap at
     *        Refer to src/SwapRouter.sol for list of available options
     * @param swapData bytes variable containing all the data needed to make a swap
     *        reciever address should be the callers address
     * @param assets amount of assets to withdraw
     * @return shares amount of shares burned
     */
    function withdrawAndSwapFromCellar(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets
    ) public returns (uint256 shares) {
        // Withdraw assets from the cellar.
        shares = cellar.withdraw(assets, address(this), msg.sender);

        // Swap assets into desired token
        cellar.asset().safeApprove(address(registry.swapRouter()), assets);
        registry.swapRouter().swap(exchange, swapData);
    }

    /**
     * @notice Withdraws from a cellar and then performs a swap to another desired asset, if the
     *         withdrawn asset is not already, using permit.
     * @dev If using Uniswap V3 for swap, must specify the pool fee tier to use for each swap. For
     *      example, if there are "n" addresses in path, there should be "n-1" values specifying the
     *      fee tiers of each pool used for each swap. The current possible pool fee tiers for
     *      Uniswap V3 are 0.01% (100), 0.05% (500), 0.3% (3000), and 1% (10000). If using Uniswap
     *      V2, leave pool fees empty to use Uniswap V2 for swap.
     * @param cellar address of the cellar
     * @param exchange ENUM representing what exchange to make the swap at
     *        Refer to src/SwapRouter.sol for list of available options
     * @param swapData bytes variable containing all the data needed to make a swap
     * @param assets amount of assets to withdraw
     * @param deadline timestamp after which permit is invalid
     * @param signature a valid secp256k1 signature
     * @return shares amount of shares burned
     */
    function withdrawAndSwapFromCellarWithPermit(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares) {
        // Approve for router to burn user shares via permit.
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        cellar.permit(msg.sender, address(this), assets, deadline, v, r, s);

        // Withdraw assets from the cellar and swap to another asset if necessary.
        shares = withdrawAndSwapFromCellar(cellar, exchange, swapData, assets);
    }

    /**
     * @notice Withdraws from a multi assset cellar and then performs swaps to another desired asset, if the
     *         withdrawn asset is not already.
     * @dev If using Uniswap V3 for swap, must specify the pool fee tier to use for each swap. For
     *      example, if there are "n" addresses in path, there should be "n-1" values specifying the
     *      fee tiers of each pool used for each swap. The current possible pool fee tiers for
     *      Uniswap V3 are 0.01% (100), 0.05% (500), 0.3% (3000), and 1% (10000). If using Uniswap
     *      V2, leave pool fees empty to use Uniswap V2 for swap.
     * @param cellar address of the cellar
     * @param exchange ENUM representing what exchange to make the swap at
     *        Refer to src/SwapRouter.sol for list of available options
     * @param swapData bytes variable containing all the data needed to make a swap
     *        reciever address should be the callers address
     * @param assets amount of assets to withdraw
     * @return shares amount of shares burned
     */
    function withdrawFromPositionsIntoSingleAsset(
        Cellar cellar,
        SwapRouter.Exchange[] calldata exchange,
        bytes[] calldata swapData,
        uint256 assets
    ) public returns (uint256 shares) {
        //TODO Brian add the balanceOf checks to make sure nothing is left in the router
        // Withdraw assets from the cellar.
        ERC20[] memory receivedAssets;
        uint256[] memory assetsOut;

        (shares, receivedAssets, assetsOut) = cellar.withdrawFromPositions(assets, address(this), msg.sender);

        //need to approve the swaprouter to spend the cellar router assets
        for (uint256 i = 0; i < assetsOut.length; i++) {
            receivedAssets[i].safeApprove(address(registry.swapRouter()), assetsOut[i]);
        }
        registry.swapRouter().multiSwap(exchange, swapData);

        //So if we aren't summing everthing together, then transferring out at the end, we need to handle the edge case where the user wants one of the assets they get from the cellar and isn't making a swap
    }

    // ========================================= HELPER FUNCTIONS =========================================

    /**
     * @notice Split a signature into its components.
     * @param signature a valid secp256k1 signature
     * @return v a component of the secp256k1 signature
     * @return r a component of the secp256k1 signature
     * @return s a component of the secp256k1 signature
     */
    function _splitSignature(bytes memory signature)
        internal
        pure
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        if (signature.length != 65) revert USR_InvalidSignature(signature.length, 65);

        // Read each parameter directly from the signature's memory region.
        assembly {
            // Place first word on the stack at r.
            r := mload(add(signature, 32))

            // Place second word on the stack at s.
            s := mload(add(signature, 64))

            // Place final byte on the stack at v.
            v := byte(0, mload(add(signature, 96)))
        }
    }
}
