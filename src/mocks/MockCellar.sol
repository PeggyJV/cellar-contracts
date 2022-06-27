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
        string memory _name,
        string memory _symbol
    ) Cellar(_registry, _asset, _positions, _name, _symbol) {}

    function depositIntoPosition(
        address position,
        uint256 amount,
        address mintSharesTo
    ) external returns (uint256 shares) {
        uint256 amountInAssets = registry.priceRouter().getValue(ERC4626(position).asset(), amount, asset);
        shares = previewDeposit(amountInAssets);

        deal(address(ERC4626(position).asset()), address(this), amount);

        getPositionData[position].highWatermark += amount.toInt256();

        ERC4626(position).deposit(amount, address(this));

        _mint(mintSharesTo, shares);
    }

    function depositIntoPosition(address position, uint256 amount) public returns (uint256 shares) {
        uint256 amountInAssets = registry.priceRouter().getValue(ERC4626(position).asset(), amount, asset);
        shares = previewDeposit(amountInAssets);

        deal(address(ERC4626(position).asset()), address(this), amount);

        getPositionData[position].highWatermark += amount.toInt256();
        totalSupply += shares;

        ERC4626(position).deposit(amount, address(this));
    }
}
