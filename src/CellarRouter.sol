// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, ERC20, SafeTransferLib } from "src/base/ERC4626.sol";
import { Registry } from "src/Registry.sol";
import { Cellar } from "src/base/Cellar.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ICellarRouter } from "src/interfaces/ICellarRouter.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";

/**
 * @title Sommelier Cellar Router
 * @notice Enables depositing/withdrawing from cellars using permits and swapping from/to different
 *         assets before/after depositing/withdrawing.
 * @author Brian Le
 */
contract CellarRouter is ICellarRouter {
    using SafeTransferLib for ERC20;

    uint256 public constant SWAP_ROUTER_REGISTRY_SLOT = 1;
    /**
     * @notice Uniswap V3 swap router contract. Used for swapping if pool fees are specified.
     */
    IUniswapV3Router public immutable uniswapV3Router; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    // TODO :: HARDCODE AAVE CELLAR TO IMPLEMENT withdrawAndSwap
    /**
     * @notice Uniswap V2 swap router contract. Used for swapping if pool fees are not specified.
     */
    IUniswapV2Router public immutable uniswapV2Router; // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Registry contract used to get most current swap router.
     */
    Registry public immutable registry;

    /**
     * @param _registry address of the registry contract
     */
    constructor(
        Registry _registry,
        IUniswapV3Router _uniswapV3Router,
        IUniswapV2Router _uniswapV2Router
    ) {
        registry = _registry;
        uniswapV3Router = _uniswapV3Router;
        uniswapV2Router = _uniswapV2Router;
    }

    // ======================================= DEPOSIT OPERATIONS =======================================

    /**
     * @notice Deposit assets into a cellar using permit.
     * @param cellar address of the cellar to deposit into
     * @param assets amount of assets to deposit
     * @param deadline timestamp after which permit is invalid
     * @param signature a valid secp256k1 signature
     * @return shares amount of shares minted
     */
    function depositWithPermit(
        Cellar cellar,
        uint256 assets,
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
        shares = cellar.deposit(assets, msg.sender);
    }

    /**
     * @notice Deposit into a cellar by first performing a swap to the cellar's current asset.
     * @dev Uses the swap router to perform the swap
     * @param cellar address of the cellar
     * @param exchange value representing what exchange to make the swap at, refer to
     *                 `SwapRouter.sol` for list of available options
     * @param swapData bytes variable containing all the data needed to make a swap, refer to
     *                 `SwapRouter.sol` to see what parameters need to be encoded for each exchange
     * @param assets amount of assets to swap, must match initial swap asset in swapData
     * @param assetIn ERC20 token used to swap for deposit token
     * @return shares amount of shares minted
     */
    function depositAndSwap(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        ERC20 assetIn
    ) public returns (uint256 shares) {
        // Transfer assets from the user to the router.
        assetIn.safeTransferFrom(msg.sender, address(this), assets);

        // Swap assets into desired token
        SwapRouter swapRouter = SwapRouter(registry.getAddress(SWAP_ROUTER_REGISTRY_SLOT));
        assetIn.safeApprove(address(swapRouter), assets);
        ERC20 assetOut = cellar.asset();
        assets = swapRouter.swap(exchange, swapData, address(this), assetIn, assetOut);

        // Approve the cellar to spend assets.
        assetOut.safeApprove(address(cellar), assets);

        // Deposit assets into the cellar.
        shares = cellar.deposit(assets, msg.sender);

        // Transfer any remaining assetIn back to sender.
        uint256 remainingBalance = assetIn.balanceOf(address(this));
        if (remainingBalance != 0) assetIn.transfer(msg.sender, remainingBalance);
    }

    /**
     * @notice Deposit into a cellar by first performing a swap to the cellar's current asset.
     * @dev Uses the swap router to perform the swap
     * @param cellar address of the cellar to deposit into
     * @param exchange value representing what exchange to make the swap at, refer to
     *                 `SwapRouter.sol` for list of available options
     * @param swapData bytes variable containing all the data needed to make a swap, refer to
     *                 `SwapRouter.sol` to see what parameters need to be encoded for each exchange
     * @param assets amount of assets to swap, must match initial swap asset in swapData
     * @param assetIn ERC20 asset caller wants to swap and deposit with
     * @param deadline timestamp after which permit is invalid
     * @param signature a valid secp256k1 signature
     * @return shares amount of shares minted
     */
    function depositAndSwapWithPermit(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        ERC20 assetIn,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares) {
        // Approve for router to burn user shares via permit.
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        assetIn.permit(msg.sender, address(this), assets, deadline, v, r, s);

        // Deposit assets into the cellar using a swap if necessary.
        shares = depositAndSwap(cellar, exchange, swapData, assets, assetIn);
    }

    // ======================================= AAVE V2 CELLAR DEPOSIT OPERATIONS =======================================

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
        ERC4626 cellar,
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
     * @param cellar address of the cellar to deposit into
     * @param path array of [token1, token2, token3] that specifies the swap path on Sushiswap
     * @param poolFees amount out of 1e4 (eg. 10000 == 1%) that represents the fee tier to use for each swap
     * @param assets amount of assets to deposit
     * @param assetsOutMin minimum amount of assets received from swap
     * @param receiver address receiving the shares
     * @return shares amount of shares minted
     */
    function depositAndSwapIntoCellar(
        ERC4626 cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver
    ) public returns (uint256 shares) {
        // Retrieve the asset being swapped and asset of cellar.
        ERC20 asset = cellar.asset();
        ERC20 assetIn = ERC20(path[0]);

        // Transfer assets from the user to the router.
        assetIn.safeTransferFrom(msg.sender, address(this), assets);

        // Check whether a swap is necessary. If not, skip swap and deposit into cellar directly.
        if (assetIn != asset) assets = _swap(path, poolFees, assets, assetsOutMin);

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
     * @param path array of [token1, token2, token3] that specifies the swap path on Sushiswap
     * @param poolFees amount out of 1e4 (eg. 10000 == 1%) that represents the fee tier to use for each swap
     * @param assets amount of assets to deposit
     * @param assetsOutMin minimum amount of assets received from swap
     * @param receiver address receiving the shares
     * @param deadline timestamp after which permit is invalid
     * @param signature a valid secp256k1 signature
     * @return shares amount of shares minted
     */
    function depositAndSwapIntoCellarWithPermit(
        ERC4626 cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares) {
        // Retrieve the asset being swapped.
        ERC20 assetIn = ERC20(path[0]);

        // Approve for router to burn user shares via permit.
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        assetIn.permit(msg.sender, address(this), assets, deadline, v, r, s);

        // Deposit assets into the cellar using a swap if necessary.
        shares = depositAndSwapIntoCellar(cellar, path, poolFees, assets, assetsOutMin, receiver);
    }

    // ======================================= WITHDRAW OPERATIONS =======================================

    /**
     * @notice Withdraws from a cellar and then performs swap(s) to another desired asset.
     * @dev Permission is required from caller for router to burn shares. Please make sure that
     *      caller has approved the router to spend their shares.
     * @param cellar address of the cellar
     * @param exchanges value representing what exchange to make the swap at, refer to
     *                  `SwapRouter.sol` for list of available options
     * @param swapDatas bytes variable containing all the data needed to make a swap, refer to
     *                  `SwapRouter.sol` to see what parameters need to be encoded for each exchange
     * @param assets amount of assets to withdraw
     * @param receiver the address swapped tokens are sent to
     * @return shares amount of shares burned
     */
    //TODO so if a cellar has multiple positions that share the same asset does this break?
    function withdrawAndSwap(
        Cellar cellar,
        SwapRouter.Exchange[] calldata exchanges,
        bytes[] calldata swapDatas,
        uint256 assets,
        address receiver
    ) public returns (uint256 shares) {
        // Withdraw from the cellar. May potentially receive multiple assets
        shares = cellar.withdraw(assets, address(this), msg.sender);

        // Get the address of the swap router.
        SwapRouter swapRouter = SwapRouter(registry.getAddress(SWAP_ROUTER_REGISTRY_SLOT));

        // Get all the assets that could potentially have been received.
        ERC20[] memory positionAssets = cellar.getPositionAssets();

        _withdraw(receiver, swapRouter, swapDatas, positionAssets, exchanges);
    }

    //** WITHDRAW 1.5 */
    function withdrawAndSwapLegacy(
        Cellar cellar,
        SwapRouter.Exchange[] calldata exchanges,
        bytes[] calldata swapDatas,
        uint256 assets,
        address receiver
    ) public returns (uint256 shares) {
        // Withdraw from the cellar. May potentially receive multiple assets
        shares = cellar.withdraw(assets, address(this), msg.sender);

        // Get the address of the swap router.
        SwapRouter swapRouter = SwapRouter(registry.getAddress(SWAP_ROUTER_REGISTRY_SLOT));

        // Get all the assets that could potentially have been received.
        ERC20[] memory positionAssets = _getPositionAssets(cellar);

        _withdraw(receiver, swapRouter, swapDatas, positionAssets, exchanges);
    }

    /**
     * @notice Withdraws from a cellar and then performs swap(s) to another desired asset, using permit.
     * @dev Permission is required from caller for router to burn shares. Please make sure that
     *      caller has approved the router to spend their shares.
     * @param cellar address of the cellar
     * @param exchanges value representing what exchange to make the swap at, refer to
     *                  `SwapRouter.sol` for list of available options
     * @param swapDatas bytes variable containing all the data needed to make a swap, refer to
     *                  `SwapRouter.sol` to see what parameters need to be encoded for each exchange
     * @param sharesToRedeem amount of shares to withdraw
     * @param deadline timestamp after which permit is invalid
     * @param signature a valid secp256k1 signature
     * @param receiver the address swapped tokens are sent to
     * @return shares amount of shares burned
     */
    function withdrawAndSwapWithPermit(
        Cellar cellar,
        SwapRouter.Exchange[] calldata exchanges,
        bytes[] calldata swapDatas,
        uint256 sharesToRedeem,
        uint256 deadline,
        bytes memory signature,
        address receiver
    ) external returns (uint256 shares) {
        // Approve for router to burn user shares via permit.
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        cellar.permit(msg.sender, address(this), sharesToRedeem, deadline, v, r, s);

        uint256 assets = cellar.previewRedeem(sharesToRedeem);

        // Withdraw assets from the cellar and swap to another asset if necessary.
        shares = withdrawAndSwap(cellar, exchanges, swapDatas, assets, receiver);
    }

    // ======================================= AAVE V2 CELLAR WITHDRAW OPERATIONS =======================================

    /**
     * @notice Withdraws from a cellar and then performs a swap to another desired asset, if the
     *         withdrawn asset is not already.
     * @dev Permission is required from caller for router to burn shares. Please make sure that
     *      caller has approved the router to spend their shares.
     * @dev If using Uniswap V3 for swap, must specify the pool fee tier to use for each swap. For
     *      example, if there are "n" addresses in path, there should be "n-1" values specifying the
     *      fee tiers of each pool used for each swap. The current possible pool fee tiers for
     *      Uniswap V3 are 0.01% (100), 0.05% (500), 0.3% (3000), and 1% (10000). If using Uniswap
     *      V2, leave pool fees empty to use Uniswap V2 for swap.
     * @param cellar address of the cellar
     * @param path array of [token1, token2, token3] that specifies the swap path on swap
     * @param poolFees amount out of 1e4 (eg. 10000 == 1%) that represents the fee tier to use for each swap
     * @param assets amount of assets to withdraw
     * @param assetsOutMin minimum amount of assets received from swap
     * @param receiver address receiving the assets
     * @return shares amount of shares burned
     */
    function withdrawAndSwapFromCellar(
        ERC4626 cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver
    ) public returns (uint256 shares) {
        ERC20 asset = cellar.asset();
        ERC20 assetOut = ERC20(path[path.length - 1]);

        // Withdraw assets from the cellar.
        shares = cellar.withdraw(assets, address(this), msg.sender);

        // Check whether a swap is necessary. If not, skip swap and transfer withdrawn assets to receiver.
        if (assetOut != asset) assets = _swap(path, poolFees, assets, assetsOutMin);

        // Transfer assets from the router to the receiver.
        assetOut.safeTransfer(receiver, assets);
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
     * @param path array of [token1, token2, token3] that specifies the swap path on swap
     * @param poolFees amount out of 1e4 (eg. 10000 == 1%) that represents the fee tier to use for each swap
     * @param assets amount of assets to withdraw
     * @param assetsOutMin minimum amount of assets received from swap
     * @param receiver address receiving the assets
     * @param deadline timestamp after which permit is invalid
     * @param signature a valid secp256k1 signature
     * @return shares amount of shares burned
     */
    function withdrawAndSwapFromCellarWithPermit(
        ERC4626 cellar,
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares) {
        // Approve for router to burn user shares via permit.
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        cellar.permit(msg.sender, address(this), assets, deadline, v, r, s);

        // Withdraw assets from the cellar and swap to another asset if necessary.
        shares = withdrawAndSwapFromCellar(cellar, path, poolFees, assets, assetsOutMin, receiver);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    /**
     * @notice Attempted an operation with an invalid signature.
     * @param signatureLength length of the signature
     * @param expectedSignatureLength expected length of the signature
     */
    error CellarRouter__InvalidSignature(uint256 signatureLength, uint256 expectedSignatureLength);

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
        if (signature.length != 65) revert CellarRouter__InvalidSignature(signature.length, 65);

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

    /**
     * @notice Perform a swap using Uniswap.
     * @dev If using Uniswap V3 for swap, must specify the pool fee tier to use for each swap. For
     *      example, if there are "n" addresses in path, there should be "n-1" values specifying the
     *      fee tiers of each pool used for each swap. The current possible pool fee tiers for
     *      Uniswap V3 are 0.01% (100), 0.05% (500), 0.3% (3000), and 1% (10000). If using Uniswap
     *      V2, leave pool fees empty to use Uniswap V2 for swap.
     * @param path array of [token1, token2, token3] that specifies the swap path on swap
     * @param poolFees amount out of 1e4 (eg. 10000 == 1%) that represents the fee tier to use for each swap
     * @param assets amount of assets to withdraw
     * @param assetsOutMin minimum amount of assets received from swap
     * @return assetsOut amount of assets received after swap
     */
    function _swap(
        address[] calldata path,
        uint24[] calldata poolFees,
        uint256 assets,
        uint256 assetsOutMin
    ) internal returns (uint256 assetsOut) {
        // Retrieve the asset being swapped.
        ERC20 assetIn = ERC20(path[0]);

        // Check whether to use Uniswap V2 or Uniswap V3 for swap.
        if (poolFees.length == 0) {
            // If no pool fees are specified, use Uniswap V2 for swap.

            // Approve assets to be swapped through the router.
            assetIn.safeApprove(address(uniswapV2Router), assets);

            // Execute the swap.
            uint256[] memory amountsOut = uniswapV2Router.swapExactTokensForTokens(
                assets,
                assetsOutMin,
                path,
                address(this),
                block.timestamp + 60
            );

            assetsOut = amountsOut[amountsOut.length - 1];
        } else {
            // If pool fees are specified, use Uniswap V3 for swap.

            // Approve assets to be swapped through the router.
            assetIn.safeApprove(address(uniswapV3Router), assets);

            // Encode swap parameters.
            bytes memory encodePackedPath = abi.encodePacked(address(assetIn));
            for (uint256 i = 1; i < path.length; i++)
                encodePackedPath = abi.encodePacked(encodePackedPath, poolFees[i - 1], path[i]);

            // Execute the swap.
            assetsOut = uniswapV3Router.exactInput(
                IUniswapV3Router.ExactInputParams({
                    path: encodePackedPath,
                    recipient: address(this),
                    deadline: block.timestamp + 60,
                    amountIn: assets,
                    amountOutMinimum: assetsOutMin
                })
            );
        }
    }

    function _withdraw(
        address receiver,
        address swapRouter,
        bytes[] calldata swapDatas,
        ERC20[] positionAssets,
        SwapRouter.Exchange[] calldata exchanges
    ) internal {
        if (swapDatas.length != 0) {
            // Encode data used to perform swap.
            bytes[] memory data = new bytes[](swapDatas.length);
            for (uint256 i; i < swapDatas.length; i++) {
                // Grab path data from swapDatas to pass in assetIn and assetOut to swap router.
                address[] memory path = abi.decode(swapDatas[i], (address[]));
                data[i] = abi.encodeCall(
                    SwapRouter.swap,
                    (exchanges[i], swapDatas[i], receiver, ERC20(path[0]), ERC20(path[path.length - 1]))
                );
            }

            // Approve swap router to swap each asset.
            // TODO:: CHECK IF ALLOWANCE IS ALREADY MAX AND SKIP :: safe guard here for tokens that dont allow multiple approvals
            for (uint256 i; i < positionAssets.length; i++)
                positionAssets[i].safeApprove(address(swapRouter), type(uint256).max);

            // Execute swap(s).
            swapRouter.multicall(data);
        }

        for (uint256 i; i < positionAssets.length; i++) {
            ERC20 asset = positionAssets[i];

            // Reset approvals.
            // TODO:: CHECK IF APPROVALS ARE ALREADY 0 AND SKIP IF YES
            asset.safeApprove(address(swapRouter), 0);

            // Transfer remaining unswapped balances to receiver.
            uint256 remainingBalance = asset.balanceOf(address(this));
            if (remainingBalance != 0) asset.transfer(receiver, remainingBalance);
        }
    }
}
