// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

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

    ISushiSwapRouter public swapRouter;

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

    function beforeWithdraw(uint256 assets, uint256) internal override {
        uint256 currentHoldings = totalHoldings();

        if (assets > currentHoldings) {
            uint256 currentTotalAssets = totalAssets();

            uint256 holdingsMissingForWithdraw = assets - currentHoldings;
            uint256 holdingsMissingForTarget = currentTotalAssets.mulDivDown(targetHoldingsPercent, DENOMINATOR);

            assets = MathUtils.min(holdingsMissingForWithdraw + holdingsMissingForTarget, currentTotalAssets);

            uint256 leftToWithdraw = assets;

            for (uint256 i = positions.length - 1; ; i--) {
                ERC4626 position = positions[i];
                PositionData memory positionData = getPositionData[position];

                uint256 positionBalance = positionData.balance;

                if (positionBalance == 0) continue;

                uint256 assetsToWithdraw = MathUtils.min(positionBalance, leftToWithdraw);

                getPositionData[position].balance -= uint112(assetsToWithdraw);

                leftToWithdraw -= assetsToWithdraw;

                position.withdraw(assetsToWithdraw, address(this), address(this));

                uint256 assetsOutMin = assetsToWithdraw.mulDivDown(DENOMINATOR - positionData.maxSlippage, DENOMINATOR);

                address[] memory path = positionData.pathToAsset;
                if (path[0] != path[path.length - 1]) swap(assetsToWithdraw, assetsOutMin, path);

                if (leftToWithdraw == 0) break;
            }

            totalBalance -= assets;
        }
    }

    function rebalance(
        ERC4626 fromPosition,
        ERC4626 toPosition,
        uint256 assetsFrom,
        uint256 assetsToMin,
        address[] memory path
    ) public override onlyOwner returns (uint256 assetsTo) {
        if (address(fromPosition) != address(this)) _withdrawFromPosition(fromPosition, assetsFrom);

        assetsTo = ERC20(path[0]) != ERC20(path[path.length - 1]) ? swap(assetsFrom, assetsToMin, path) : assetsFrom;

        if (address(toPosition) != address(this)) _depositIntoPosition(toPosition, assetsTo);
    }

    // ============================================= SWAP UTILS =============================================

    function swap(
        uint256 assets,
        uint256 assetsToMin,
        address[] memory path
    ) internal returns (uint256) {
        ERC20(path[0]).safeApprove(address(swapRouter), assets);

        uint256[] memory swapOutput = swapRouter.swapExactTokensForTokens(
            assets,
            assetsToMin,
            path,
            address(this),
            block.timestamp + 60
        );

        return swapOutput[swapOutput.length - 1];
    }
}
