// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IComet } from "src/interfaces/external/Compound/IComet.sol";

/**
 * @title Compound V3 Helper Logic
 * @notice Contains shared logic multiple Compound V3 Adaptors use.
 * @author crispymangoes
 */
contract V3Helper {
    using Math for uint256;

    /**
     * @notice The maximum number of collateral assets a comet can have.
     * @dev If a cellar has an open position with a comet, and more collateral assets are added
     *      to the comet, and the maxNumberOfAssets is exceeded, `getAccountHealthFactor`
     *      will always return zero, so the Cellar must pay back all debt before being able to
     *      remove collateral, or borrow again.
     * @dev The purpose of this logic is to constrain an unbounded for loop, and so that
     *      rebalance gas costs can not be significantly increased by Compound governance.
     */
    uint8 public immutable maxNumberOfAssets;

    constructor(uint8 _maxNumberOfAssets) {
        maxNumberOfAssets = _maxNumberOfAssets;
    }

    /**
     * @notice Returns an accounts health factor for a given comet.
     * @dev Returns type(uint256).max if no debt is owed.
     * @dev Returns 0 if `maxNumberOfAssets` is exceeded. See `maxNumberOfAssets` above.
     */
    function getAccountHealthFactor(IComet comet, address account) public view returns (uint256) {
        // Get the amount of base debt owed adjusted for price.
        uint256 borrowBalanceInVirtualBase;
        {
            uint256 borrowBalanceInBase = comet.borrowBalanceOf(account);
            if (borrowBalanceInBase == 0) return type(uint256).max;
            uint8 baseDecimals = comet.baseToken().decimals();
            address basePriceFeed = comet.baseTokenPriceFeed();
            uint256 basePriceInVirtualBase = comet.getPrice(basePriceFeed);
            borrowBalanceInVirtualBase = borrowBalanceInBase.mulDivDown(basePriceInVirtualBase, 10 ** baseDecimals);
        }

        uint8 numberOfAssets = comet.numAssets();
        // If numberOfAssets exceeds maxNumberOfAssets then we can not safely calculate the health factor
        // without expending a large amount of gas.
        if (numberOfAssets > maxNumberOfAssets) return 0;

        uint256 riskAdjustedCollateralValueInVirtualBase;
        // Iterate through assets, and determine the risk adjusted collateral value.
        for (uint8 i; i < numberOfAssets; ++i) {
            IComet.AssetInfo memory info = comet.getAssetInfo(i);

            // Check if we have a collateral balance.
            (uint256 collateralBalance, ) = comet.userCollateral(account, info.asset);

            if (collateralBalance == 0) continue;

            // Get the value of collateral in USD.
            uint256 collateralPriceInVirtualBase = comet.getPrice(info.priceFeed);

            uint8 collateralDecimals = ERC20(info.asset).decimals();

            uint256 collateralValueInVirtualBase = collateralBalance.mulDivDown(
                collateralPriceInVirtualBase,
                10 ** collateralDecimals
            );

            riskAdjustedCollateralValueInVirtualBase += collateralValueInVirtualBase.mulDivDown(
                info.liquidateCollateralFactor,
                1e18
            );
        }

        return riskAdjustedCollateralValueInVirtualBase.mulDivDown(1e18, borrowBalanceInVirtualBase);
    }
}
