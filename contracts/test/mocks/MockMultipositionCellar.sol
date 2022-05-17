// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { MultipositionCellar } from "../../templates/MultipositionCellar.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { ERC4626 } from "../../interfaces/ERC4626.sol";
import { ISushiSwapRouter } from "../../interfaces/ISushiSwapRouter.sol";
import { MathUtils } from "../../utils/MathUtils.sol";

import "../../Errors.sol";

contract MockMultipositionCellar is MultipositionCellar {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    ISushiSwapRouter public immutable swapRouter;

    constructor(
        ERC20 _asset,
        ERC4626[] memory _positions,
        address[][] memory _paths,
        uint32[] memory _maxSlippages,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        ISushiSwapRouter _swapRouter
    ) MultipositionCellar(_asset, _positions, _paths, _maxSlippages, _name, _symbol, _decimals) {
        swapRouter = _swapRouter;
    }

    // TODO: update this when testing positions in different denoms
    function priceAssetsFrom(
        ERC20,
        ERC20,
        uint256 assets
    ) public pure override returns (uint256) {
        return assets;
    }

    function depositIntoPosition(
        ERC4626 position,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        ERC20 positionAsset = position.asset();
        positionAsset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        _depositIntoPosition(position, assets);
    }

    function withdrawFromPosition(
        ERC4626 position,
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        _withdrawFromPosition(position, assets);

        ERC20 positionAsset = position.asset();
        positionAsset.safeTransfer(receiver, assets);
    }

    // ============================================= SWAP UTILS =============================================

    function _swap(
        ERC20 positionAsset,
        uint256 assets,
        uint256 assetsOutMin,
        address[] memory path
    ) internal override returns (uint256) {
        ERC20 assetIn = ERC20(path[0]);
        ERC20 assetOut = ERC20(path[path.length - 1]);

        // Ensure that the asset being swapped matches the asset received by the position.
        if (assetOut != positionAsset) revert USR_InvalidSwap(address(assetOut), address(positionAsset));

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
