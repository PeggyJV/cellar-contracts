// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { MultipositionCellar } from "../../templates/MultipositionCellar.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { ERC4626 } from "../../interfaces/ERC4626.sol";
import { MathUtils } from "../../utils/MathUtils.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { MockPriceOracle } from "./MockPriceOracle.sol";

import "../../Errors.sol";

contract MockMultipositionCellar is MultipositionCellar {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    MockPriceOracle public immutable priceOracle;

    constructor(
        ERC20 _asset,
        ERC4626[] memory _positions,
        address[][] memory _paths,
        uint32[] memory _maxSlippages,
        ISwapRouter _swapRouter,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        MockPriceOracle _priceOracle
    ) MultipositionCellar(_asset, _positions, _paths, _maxSlippages, _swapRouter, _name, _symbol, _decimals) {
        priceOracle = _priceOracle;
    }

    function convertToAssets(ERC20 positionAsset, uint256 assets) public view override returns (uint256) {
        return
            MathUtils.changeDecimals(
                // Use 1e8 pairs with non-ETH denominations (eg. USDC).
                assets.mulDivDown(priceOracle.getLatestPrice(address(positionAsset)), 1e8),
                positionAsset.decimals(),
                decimals
            );
    }

    function depositIntoPosition(
        ERC4626 position,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        require((shares = previewDeposit(convertToAssets(position.asset(), assets))) != 0, "ZERO_SHARES");

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
        shares = previewWithdraw(convertToAssets(position.asset(), assets));

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        _withdrawFromPosition(position, assets);

        ERC20 positionAsset = position.asset();
        positionAsset.safeTransfer(receiver, assets);
    }
}
