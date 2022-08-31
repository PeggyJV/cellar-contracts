// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
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

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Registry contract used to get most current swap router.
     */
    Registry public immutable registry;

    /**
     * @param _registry address of the registry contract
     */
    constructor(Registry _registry) {
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
    function depositWithPermit(
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
     * @notice Deposit into a cellar by first performing a swap to the cellar's current asset.
     * @dev Uses the swap router to perform the swap
     * @param cellar address of the cellar
     * @param exchange value representing what exchange to make the swap at, refer to
     *                 `SwapRouter.sol` for list of available options
     * @param swapData bytes variable containing all the data needed to make a swap, refer to
     *                 `SwapRouter.sol` to see what parameters need to be encoded for each exchange
     * @param assets amount of assets to swap, must match initial swap asset in swapData
     * @param receiver address to receive the cellar shares
     * @param assetIn ERC20 token used to swap for deposit token
     * @return shares amount of shares minted
     */
    function depositAndSwap(
        Cellar cellar,
        SwapRouter.Exchange exchange,
        bytes calldata swapData,
        uint256 assets,
        address receiver,
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
        shares = cellar.deposit(assets, receiver);

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
     * @param receiver address to receive the cellar shares
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
        address receiver,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares) {
        // Approve for router to burn user shares via permit.
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        assetIn.permit(msg.sender, address(this), assets, deadline, v, r, s);

        // Deposit assets into the cellar using a swap if necessary.
        shares = depositAndSwap(cellar, exchange, swapData, assets, receiver, assetIn);
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
        ERC20[] memory positionAssets = _getPositionAssets(cellar);

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
            for (uint256 i; i < positionAssets.length; i++)
                positionAssets[i].safeApprove(address(swapRouter), type(uint256).max);

            // Execute swap(s).
            swapRouter.multicall(data);
        }

        for (uint256 i; i < positionAssets.length; i++) {
            ERC20 asset = positionAssets[i];

            // Reset approvals.
            asset.safeApprove(address(swapRouter), 0);

            // Transfer remaining unswapped balances to receiver.
            uint256 remainingBalance = asset.balanceOf(address(this));
            if (remainingBalance != 0) asset.transfer(receiver, remainingBalance);
        }
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
     * @param assets amount of assets to withdraw
     * @param deadline timestamp after which permit is invalid
     * @param signature a valid secp256k1 signature
     * @param receiver the address swapped tokens are sent to
     * @return shares amount of shares burned
     */
    function withdrawAndSwapWithPermit(
        Cellar cellar,
        SwapRouter.Exchange[] calldata exchanges,
        bytes[] calldata swapDatas,
        uint256 assets,
        uint256 deadline,
        bytes memory signature,
        address receiver
    ) external returns (uint256 shares) {
        // Approve for router to burn user shares via permit.
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        cellar.permit(msg.sender, address(this), assets, deadline, v, r, s);

        // Withdraw assets from the cellar and swap to another asset if necessary.
        shares = withdrawAndSwap(cellar, exchanges, swapDatas, assets, receiver);
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
     * @notice Used to determine the amounts of assets Router had using current balances and amountsReceived.
     * @param assets array of ERC20 tokens to query the balances of
     * @param amountsReceived the amount of each assets received
     * @return balancesBefore array of balances before amounts were received
     */
    function _getBalancesBefore(ERC20[] memory assets, uint256[] memory amountsReceived)
        internal
        view
        returns (uint256[] memory balancesBefore)
    {
        balancesBefore = new uint256[](assets.length);

        for (uint256 i; i < assets.length; i++) {
            ERC20 asset = assets[i];

            balancesBefore[i] = asset.balanceOf(address(this)) - amountsReceived[i];
        }
    }

    /**
     * @notice Find what assets a cellar's positions uses.
     * @param cellar address of the cellar
     * @return assets array of assets that make up cellar's positions
     */
    function _getPositionAssets(Cellar cellar) internal view returns (ERC20[] memory assets) {
        address[] memory positions = cellar.getPositions();

        assets = new ERC20[](positions.length);

        for (uint256 i; i < positions.length; i++) {
            address position = positions[i];
            (Cellar.PositionType positionType, , ) = cellar.getPositionData(position);

            assets[i] = positionType == Cellar.PositionType.ERC20 ? ERC20(position) : ERC4626(position).asset();
        }
    }
}
