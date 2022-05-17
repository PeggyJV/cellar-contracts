// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { ICellar } from "../../interfaces/ICellar.sol";
import { ERC4626 } from "../../interfaces/ERC4626.sol";
import { MockSwapRouter } from "./MockSwapRouter.sol";
import { ISwapRouter } from "../../interfaces/ISwapRouter.sol";

import "../../Errors.sol";
import { ICellarRouter } from "../../interfaces/ICellarRouter.sol";

contract MockCellarRouter is ICellarRouter {
    using SafeTransferLib for ERC20;

    // ========================================= SWAP OPERATIONS =========================================

    MockSwapRouter public immutable swapRouter;

    constructor(MockSwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    function safeSwap(
        ERC20 positionAsset,
        uint256 assets,
        uint256 assetsOutMin,
        address[] memory path
    ) internal returns (uint256) {
        ERC20 assetIn = ERC20(path[0]);
        ERC20 assetOut = ERC20(path[path.length - 1]);

        // Ensure that the asset being swapped matches the asset received by the position.
        if (assetOut != positionAsset) revert USR_InvalidSwap(address(assetOut), address(positionAsset));

        // Check whether a swap is necessary. If not, just return back assets.
        if (assetIn == assetOut) return assets;

        // Approve assets to be swapped through the router.
        assetIn.safeApprove(address(swapRouter), assets);

        bytes memory encodePackedPath = abi.encodePacked(path[0]);
        uint24 POOL_FEE = 3000;
        for (uint256 i = 1; i < path.length; i++) {
            encodePackedPath = abi.encodePacked(encodePackedPath, POOL_FEE, path[i]);
        }

        // Prepare the parameters for the swap.
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: encodePackedPath,
            recipient: address(this),
            deadline: block.timestamp + 60,
            amountIn: assets,
            amountOutMinimum: assetsOutMin
        });

        // Executes the swap.
        return swapRouter.exactInput(params);
    }

    // ======================================= ROUTER OPERATIONS =======================================

    /**
     * @notice Deposit assets into a cellar using permit.
     * @param cellar address of the cellar to deposit into
     * @param assets amount of assets to deposit
     * @param receiver address receiving the shares
     * @param owner address that owns the assets being deposited
     * @param deadline timestamp after which permit is invalid
     * @param v used to produce valid secp256k1 signature from the caller along with r and s
     * @param r used to produce valid secp256k1 signature from the caller along with v and s
     * @param s used to produce valid secp256k1 signature from the caller along with r and v
     * @return shares amount of shares minted
     */
    function depositIntoCellarWithPermit(
        ICellar cellar,
        uint256 assets,
        address receiver,
        address owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares) {
        // Retrieve the cellar's current asset.
        ERC20 asset = cellar.asset();

        // Approve the assets from the user to the router via permit.
        asset.permit(owner, address(this), assets, deadline, v, r, s);

        // Transfer assets from the user to the router.
        asset.safeTransferFrom(owner, address(this), assets);

        // Approve the cellar to spend assets.
        asset.safeApprove(address(cellar), assets);

        // Deposit assets into the cellar.
        shares = cellar.deposit(assets, receiver);
    }

    /**
     * @notice Deposit into a cellar by first performing a swap to the cellar's current asset if necessary.
     * @param cellar address of the cellar to deposit into
     * @param path array of [token1, token2, token3] that specifies the swap path on Sushiswap
     * @param assets amount of assets to deposit
     * @param minAssetsOut minimum amount of assets received from swap
     * @param receiver address receiving the shares
     * @param owner address that owns the assets being deposited
     * @return shares amount of shares minted
     */
    function depositAndSwapIntoCellar(
        ICellar cellar,
        address[] calldata path,
        uint256 assets,
        uint256 minAssetsOut,
        address receiver,
        address owner
    ) public returns (uint256 shares) {
        // Retrieve the cellar's current asset.
        ERC20 asset = cellar.asset();

        // Transfer assets from the user to the router.
        ERC20(path[0]).safeTransferFrom(owner, address(this), assets);

        // Perform swap if to cellar's asset if necessary.
        assets = safeSwap(asset, assets, minAssetsOut, path);

        // Approve the cellar to spend assets.
        asset.safeApprove(address(cellar), assets);

        // Deposit assets into the cellar.
        shares = cellar.deposit(assets, receiver);
    }

    /**
     * @notice Deposit into a cellar by first performing a swap to the cellar's current asset if necessary.
     * @param cellar address of the cellar to deposit into
     * @param path array of [token1, token2, token3] that specifies the swap path on Sushiswap
     * @param assets amount of assets to deposit
     * @param minAssetsOut minimum amount of assets received from swap
     * @param receiver address receiving the shares
     * @param owner address that owns the assets being deposited
     * @param deadline timestamp after which permit is invalid
     * @param v used to produce valid secp256k1 signature from the caller along with r and s
     * @param r used to produce valid secp256k1 signature from the caller along with v and s
     * @param s used to produce valid secp256k1 signature from the caller along with r and v
     * @return shares amount of shares minted
     */
    function depositAndSwapIntoCellarWithPermit(
        ICellar cellar,
        address[] calldata path,
        uint256 assets,
        uint256 minAssetsOut,
        address receiver,
        address owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares) {
        // Retrieve the asset being swapped.
        ERC20 assetIn = ERC20(path[0]);

        // Approve the assets from the user to the router via permit.
        assetIn.permit(owner, address(this), assets, deadline, v, r, s);

        // Deposit assets into the cellar using a swap if necessary.
        shares = depositAndSwapIntoCellar(cellar, path, assets, minAssetsOut, receiver, owner);
    }
}
