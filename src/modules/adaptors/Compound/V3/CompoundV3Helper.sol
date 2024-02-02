// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IComet } from "src/interfaces/external/Compound/IComet.sol";

/**
 * @title Compound V3 Helper Logic
 * @notice Contains shared logic multiple Compound V3 Adaptors use.
 * @author crispymangoes
 */
contract CompoundV3Helper {
    using Math for uint256;

    /**
     * @notice Returns an accounts health factor for a given comet.
     * @dev Returns type(uint256).max if no debt is owed.
     */
    function getAccountHealthFactor(IComet comet, address account) public view returns (uint256) {
        // Get the amount of base debt owed adjusted for price.
        uint256 borrowBalanceInVirtualBase;
        {
            uint256 borrowBalanceInBase = comet.borrowBalanceOf(account);
            if (borrowBalanceInBase == 0) return type(uint256).max;
            address basePriceFeed = comet.baseTokenPriceFeed();
            uint256 basePriceInVirtualBase = comet.getPrice(basePriceFeed);
            borrowBalanceInVirtualBase = borrowBalanceInBase.mulDivDown(basePriceInVirtualBase, comet.baseScale());
        }

        uint16 assetsIn = comet.userBasic(account).assetsIn;

        uint8 numberOfAssets = comet.numAssets();

        uint256 riskAdjustedCollateralValueInVirtualBase;
        // Iterate through assets, and determine the risk adjusted collateral value.
        for (uint8 i; i < numberOfAssets; ++i) {
            if (isInAsset(assetsIn, i)) {
                IComet.AssetInfo memory info = comet.getAssetInfo(i);

                // Check if we have a collateral balance.
                (uint256 collateralBalance, ) = comet.userCollateral(account, info.asset);

                // Get the value of collateral in virtual base.
                uint256 collateralPriceInVirtualBase = comet.getPrice(info.priceFeed);

                uint256 collateralValueInVirtualBase = collateralBalance.mulDivDown(
                    collateralPriceInVirtualBase,
                    info.scale
                );

                riskAdjustedCollateralValueInVirtualBase += collateralValueInVirtualBase.mulDivDown(
                    info.liquidateCollateralFactor,
                    1e18
                );
            } // else user collateral is zero.
        }

        return riskAdjustedCollateralValueInVirtualBase.mulDivDown(1e18, borrowBalanceInVirtualBase);
    }

    /**
     * @dev Whether user has a non-zero balance of an asset, given assetsIn flags
     */
    function isInAsset(uint16 assetsIn, uint8 assetOffset) internal pure returns (bool) {
        return (assetsIn & (uint16(1) << assetOffset) != 0);
    }
}
