// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { Cellar, Registry, ERC4626, ERC20, SafeCast } from "src/base/Cellar.sol";
import { Test, console } from "@forge-std/Test.sol";

contract MockCellar is Cellar, Test {
    using SafeCast for uint256;
    using SafeCast for int256;

    constructor(
        Registry _registry,
        ERC20 _asset,
        address[] memory _positions,
        PositionType[] memory _positionTypes,
        address _holdingPosition,
        WithdrawType _withdrawType,
        string memory _name,
        string memory _symbol
    ) Cellar(_registry, _asset, _positions, _positionTypes, _holdingPosition, _withdrawType, _name, _symbol) {}

    function depositIntoPosition(
        address position,
        uint256 amount,
        address mintSharesTo
    ) external returns (uint256 shares) {
        shares = _depositIntoPosition(position, amount);

        _mint(mintSharesTo, shares);
    }

    function depositIntoPosition(address position, uint256 amount) external returns (uint256 shares) {
        shares = _depositIntoPosition(position, amount);

        totalSupply += shares;
    }

    function _depositIntoPosition(address position, uint256 amount) internal returns (uint256 shares) {
        ERC20 positionAsset = _assetOf(position);

        uint256 amountInAssets = registry.priceRouter().getValue(positionAsset, amount, asset);
        shares = previewDeposit(amountInAssets);

        deal(address(positionAsset), address(this), amount);

        _depositTo(position, amount);
    }
}
