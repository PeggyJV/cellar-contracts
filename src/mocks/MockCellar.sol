// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { Cellar, Registry, ERC4626, ERC20, SafeCast, PositionLib, PositionType } from "src/base/Cellar.sol";
import { Test, console } from "@forge-std/Test.sol";

contract MockCellar is Cellar, Test {
    using PositionLib for address;
    using SafeCast for uint256;
    using SafeCast for int256;

    constructor(
        Registry _registry,
        ERC20 _asset,
        address[] memory _positions,
        PositionType[] memory _positionTypes,
        string memory _name,
        string memory _symbol
    ) Cellar(_registry, _asset, _positions, _positionTypes, _name, _symbol) {}

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
        PositionData storage positionData = getPositionData[position];
        PositionType positionType = positionData.positionType;

        ERC20 positionAsset = position.asset(positionType);

        uint256 amountInAssets = registry.priceRouter().getValue(positionAsset, amount, asset);
        shares = previewDeposit(amountInAssets);

        deal(address(positionAsset), address(this), amount);

        positionData.highWatermark += amount.toInt256();

        position.deposit(positionType, amount);
    }
}
