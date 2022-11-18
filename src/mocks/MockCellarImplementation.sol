// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Registry, PriceRouter, ERC4626, ERC20, SafeCast, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializable } from "src/base/CellarInitializable.sol";
import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";

contract MockCellarImplementation is CellarInitializable, Test {
    using SafeCast for uint256;
    using SafeCast for int256;
    using stdStorage for StdStorage;

    constructor(Registry _registry) CellarInitializable(_registry) {}

    function depositIntoPosition(
        uint32 position,
        uint256 amount,
        address mintSharesTo
    ) external returns (uint256 shares) {
        shares = _depositIntoPosition(position, amount);

        _mint(mintSharesTo, shares);
    }

    function depositIntoPosition(uint32 position, uint256 amount) external returns (uint256 shares) {
        shares = _depositIntoPosition(position, amount);

        // Increase totalSupply by shares amount.
        stdstore.target(address(this)).sig(this.totalSupply.selector).checked_write(totalSupply + shares);
    }

    function _depositIntoPosition(uint32 position, uint256 amount) internal returns (uint256 shares) {
        ERC20 positionAsset = _assetOf(position);

        PriceRouter priceRouter = PriceRouter(registry.getAddress(2));
        uint256 amountInAssets = priceRouter.getValue(positionAsset, amount, asset);
        shares = previewDeposit(amountInAssets);

        deal(address(positionAsset), address(this), amount);

        _depositTo(position, amount);
    }
}
