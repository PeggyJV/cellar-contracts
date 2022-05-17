// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";
import { ISwapRouter } from "../interfaces/ISwapRouter.sol";

import "../Errors.sol";

library SwapUtils {
    using SafeTransferLib for ERC20;

    // Uniswap V3 contract
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /**
     * @notice Swaps assets using Uniswap V3.
     * @dev Includes checks to ensure that the asset being swapped to matches the asset received by
     *      the position and that a swap is necessary in the first place.
     * @param positionAsset asset that the position expects to receive from swap
     * @param assets amount of the incoming token
     * @param assetsOutMin minimum value of the the
     * @param path list of addresses that specify the swap path on Uniswap V3
     * @return amountOut  actual received amount of outgoing token (>=assetsOutMin)
     **/
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

        // Executes the swap and return the amount out.
        return swapRouter.exactInput(params);
    }
}
