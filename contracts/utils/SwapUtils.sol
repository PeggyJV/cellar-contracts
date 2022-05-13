// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";
import { ISushiSwapRouter } from "../interfaces/ISushiSwapRouter.sol";

import "../Errors.sol";

// TODO: use uniswap instead of sushiswap
// TODO: update router to use this library
library SwapUtils {
    using SafeTransferLib for ERC20;

    ISushiSwapRouter public constant swapRouter = ISushiSwapRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    // TODO: add natspec
    /**
     *  @dev Includes checks to ensure that the asset being swapped to matches the asset received by
     *       the position and that a swap is necessary in the first place.
     */
    function safeSwap(
        ERC4626 position,
        uint256 assets,
        uint256 assetsOutMin,
        address[] memory path
    ) internal returns (uint256) {
        ERC20 assetIn = ERC20(path[0]);
        ERC20 assetOut = ERC20(path[path.length - 1]);
        ERC20 asset = position.asset();

        // Ensure that the asset being swapped matches the asset received by the position.
        if (assetOut != asset) revert USR_InvalidSwap(address(assetOut), address(asset));

        // Check whether a swap is necessary. If not, just return back assets.
        if (assetIn == assetOut) return assets;

        // Approve assets to be swapped.
        assetIn.safeApprove(address(swapRouter), assets);

        // Perform swap to position's current asset.
        uint256[] memory swapOutput = swapRouter.swapExactTokensForTokens(
            assets,
            assetsOutMin,
            path,
            address(this),
            block.timestamp + 60
        );

        // Retrieve the final assets received from swap.
        return swapOutput[swapOutput.length - 1];
    }
}
