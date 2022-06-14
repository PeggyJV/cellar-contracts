// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC4626 } from "./base/ERC4626.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import { ICellarRouter } from "./interfaces/ICellarRouter.sol";

contract CellarRouter is ICellarRouter {
    using SafeTransferLib for ERC20;

    // ========================================== CONSTRUCTOR ==========================================
    /**
     * @notice Uniswap V3 swap router contract. Used for swapping into the current asset of a given cellar.
     */
    ISwapRouter public swapRouter; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    /**
     * @param _swapRouter Uniswap V3 swap router address
     */
    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
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
        ERC4626 cellar,
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
     * @param assetsOutMin minimum amount of assets received from swap
     * @param receiver address receiving the shares
     * @param owner address that owns the assets being deposited
     * @return shares amount of shares minted
     */
    function depositAndSwapIntoCellar(
        ERC4626 cellar,
        address[] calldata path,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        address owner
    ) public returns (uint256 shares) {
        ERC20 asset = cellar.asset();
        ERC20 assetIn = ERC20(path[0]);

        // Transfer assets from the user to the router.
        assetIn.safeTransferFrom(owner, address(this), assets);

        // Check whether a swap is necessary. If not, skip swap and deposit into cellar directly.
        if (assetIn != asset) {
            // Approve assets to be swapped through the router.
            assetIn.safeApprove(address(swapRouter), assets);

            // Prepare the parameters for the swap.
            uint24 POOL_FEE = 3000;
            bytes memory encodePackedPath = abi.encodePacked(address(assetIn));
            for (uint256 i = 1; i < path.length; i++) {
                encodePackedPath = abi.encodePacked(encodePackedPath, POOL_FEE, path[i]);
            }

            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: encodePackedPath,
                recipient: address(this),
                deadline: block.timestamp + 60,
                amountIn: assets,
                amountOutMinimum: assetsOutMin
            });

            // Executes the swap and return the amount out.
            assets = swapRouter.exactInput(params);
        }

        // Approve the cellar to spend assets.
        asset.safeApprove(address(cellar), assets);

        // Deposit assets into the cellar.
        shares = cellar.deposit(assets, receiver);
    }

    /**
     * @notice Deposit with permit into a cellar by first performing a swap to the cellar's current asset if necessary.
     * @param cellar address of the cellar to deposit into
     * @param path array of [token1, token2, token3] that specifies the swap path on Sushiswap
     * @param assets amount of assets to deposit
     * @param assetsOutMin minimum amount of assets received from swap
     * @param receiver address receiving the shares
     * @param owner address that owns the assets being deposited
     * @param deadline timestamp after which permit is invalid
     * @param v used to produce valid secp256k1 signature from the caller along with r and s
     * @param r used to produce valid secp256k1 signature from the caller along with v and s
     * @param s used to produce valid secp256k1 signature from the caller along with r and v
     * @return shares amount of shares minted
     */
    function depositAndSwapIntoCellarWithPermit(
        ERC4626 cellar,
        address[] calldata path,
        uint256 assets,
        uint256 assetsOutMin,
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
        shares = depositAndSwapIntoCellar(cellar, path, assets, assetsOutMin, receiver, owner);
    }

    /**
     * @notice Redeems `shares` from `owner` and sends `assets` of underlying tokens to `router`. 
     * Then swaps underlying tokens if necessary and sends the token specified last in the path list to the receiver.
     * @param cellar address of the cellar
     * @param path array of [token1, token2, token3] that specifies the swap path on swap
     * @param assets amount of assets to withdrawal
     * @param assetsOutMin minimum amount of assets received from swap
     * @param receiver address receiving the assets
     * @param owner address that owns the shares being
     * @return shares amount of shares burned
     */
    function withdrawAndSwapFromCellar(
        ERC4626 cellar,
        address[] calldata path,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        require(owner == msg.sender || owner == receiver, "INVALID_OWNER");

        shares = _withdrawAndSwapFromCellar(
            cellar,
            path,
            assets,
            assetsOutMin,
            receiver,
            owner
        );
    }

    /**
     * @notice Redeems with permit `shares` from `owner` and sends `assets` of underlying tokens to `router`. 
     * Then swaps underlying tokens if necessary and sends the token specified last in the path list to the receiver.
     * @param cellar address of the cellar
     * @param path array of [token1, token2, token3] that specifies the swap path on swap
     * @param assets amount of assets to withdrawal
     * @param assetsOutMin minimum amount of assets received from swap
     * @param receiver address receiving the assets
     * @param owner address that owns the shares being
     * @param deadline timestamp after which permit is invalid
     * @param v used to produce valid secp256k1 signature from the caller along with r and s
     * @param r used to produce valid secp256k1 signature from the caller along with v and s
     * @param s used to produce valid secp256k1 signature from the caller along with r and v
     * @return shares amount of shares burned
     */
    function withdrawAndSwapFromCellarWithPermit(
        ERC4626 cellar,
        address[] calldata path,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        address owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares) {
        // Approve for router to burn user shares via permit.
        cellar.permit(owner, address(this), assets, deadline, v, r, s);

        shares = _withdrawAndSwapFromCellar(
            cellar,
            path,
            assets,
            assetsOutMin,
            receiver,
            owner
        );
    }

    function _withdrawAndSwapFromCellar(
        ERC4626 cellar,
        address[] calldata path,
        uint256 assets,
        uint256 assetsOutMin,
        address receiver,
        address owner
    ) internal returns (uint256 shares) {
        ERC20 asset = cellar.asset();
        ERC20 assetOut = ERC20(path[path.length - 1]);

        // Withdraw assets from the cellar. 
        // Owner permission is required for router to burn shares
        shares = cellar.withdraw(assets, address(this), owner);

        // Check whether a swap is necessary. If not, skip swap.
        if (asset != assetOut) {
            // Approve assets to be swapped through the router.
            asset.safeApprove(address(swapRouter), assets);

            // Prepare the parameters for the swap.
            uint24 POOL_FEE = 3000;
            bytes memory encodePackedPath = abi.encodePacked(path[0]);
            for (uint256 i = 1; i < path.length; i++) {
                encodePackedPath = abi.encodePacked(encodePackedPath, POOL_FEE, path[i]);
            }

            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: encodePackedPath,
                recipient: address(this),
                deadline: block.timestamp + 60,
                amountIn: assets,
                amountOutMinimum: assetsOutMin
            });

            // Executes the swap and return the amount out.
            assets = swapRouter.exactInput(params);
        }

        // Transfer assets from the router to the receiver.
        assetOut.safeTransfer(receiver, assets);
    }
}
