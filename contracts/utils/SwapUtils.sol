// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {ERC4626} from "../interfaces/ERC4626.sol";

import "../Errors.sol";
import "../interfaces/ISwapRouter.sol";

library SwapUtils {
    using SafeTransferLib for ERC20;

    // Uniswap V3 contract
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // TODO: add natspec
    function swap(
        uint256 assetsIn,
        uint256 assetsOutMin,
        address[] memory path
    ) internal returns (uint256) {

        ERC20(path[0]).safeApprove(address(swapRouter), assetsIn);

        ISwapRouter.ExactInputParams memory params =
        ISwapRouter.ExactInputParams({
        path : abi.encodePacked(path),
        recipient : msg.sender,
        deadline : block.timestamp + 60,
        amountIn : assetsIn,
        amountOutMinimum : assetsOutMin
        });

        // Executes the swap.
        return swapRouter.exactInput(params);
    }

    /**
     * @notice Deposit into an ERC4626 position by first performing a swap to the position's current asset if necessary.
     * @param position address of the position to deposit into
     * @param path array of [token1, token2, token3] that specifies the swap path on Sushiswap
     * @param assetsIn amount of assets to deposit
     * @param assetsOutMin minimum amount of assets received from swap
     * @param receiver address receiving the shares
     * @return shares amount of shares minted
     */
    function depositAndSwap(
        ERC4626 position,
        uint256 assetsIn,
        uint256 assetsOutMin,
        address[] memory path,
        address receiver
    ) internal returns (uint256 shares) {
        ERC20 assetIn = ERC20(path[0]);
        ERC20 assetOut = ERC20(path[path.length - 1]);

        // Performing a swap to the to position's asset if necessary.
        uint256 assetsOut = assetIn != assetOut ? swap(assetsIn, assetsOutMin, path) : assetsIn;

        // Approve the position to spend assets.
        assetOut.safeApprove(address(position), assetsOut);

        // Deposit assets into the position.
        shares = position.deposit(assetsOut, receiver);
    }
}
