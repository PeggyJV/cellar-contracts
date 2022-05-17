// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {ERC4626} from "../interfaces/ERC4626.sol";


import "../Errors.sol";
import "../interfaces/ISwapRouter.sol";

library SwapUtils {
    using SafeTransferLib for ERC20;

    uint24 public constant POOL_FEE = 3000;

    // Uniswap V3 contract
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /**
     * @dev swaps input token by Uniswap V3, Includes checks to ensure that the asset being swapped to matches the asset received by
     *       the position and that a swap is necessary in the first place.
     * @param position ERC4626
     * @param assets amount of the incoming token
     * @param assetsOutMin minimum value of the the
     * @param path address array, token exchange path
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


        assetIn.safeApprove(address(swapRouter), assets);

        bytes memory encodePackedPath = abi.encodePacked(path[0]);
        for (uint256 i = 1; i < path.length; i++) {
            encodePackedPath = abi.encodePacked(
                encodePackedPath,
                POOL_FEE,
                path[i]
            );
        }

        ISwapRouter.ExactInputParams memory params =
        ISwapRouter.ExactInputParams({
        path : encodePackedPath,
        recipient : address(this),
        deadline : block.timestamp + 60,
        amountIn : assets,
        amountOutMinimum : assetsOutMin
        });

        // Executes the swap.
        return swapRouter.exactInput(params);
    }
}
