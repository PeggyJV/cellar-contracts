// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IComet } from "src/interfaces/external/Compound/IComet.sol";

// TODO claim comp rewards?
contract V3Helper {
    using Math for uint256;

    function getAccountHealthFactor(IComet comet, address account) public view returns (uint256) {
        // Get the amount of base debt owed.
        uint256 borrowBalance = comet.borrowBalanceOf(account);
        if (borrowBalance == 0) return type(uint256).max;
        uint8 baseDecimals = comet.baseToken().decimals();
        // 8 decimals is the standard decimals for compound V3 pricing.
        borrowBalance = borrowBalance.changeDecimals(baseDecimals, 8);

        // TODO this for loop should have some reasonable upper bound, so that we are not gas griefed, and if exceeded, then we return a zero maybe?
        // So fixing this would require repaying all debt so borrow balance is zero, then  we will return above, so strategist can pull collateral.
        uint8 numberOfAssets = comet.numAssets();

        uint256 riskAdjustedCollateralValueInBase;
        // Iterate through assets, and determine the risk adjusted collateral value.
        for (uint8 i; i < numberOfAssets; ++i) {
            IComet.AssetInfo memory info = comet.getAssetInfo(i);

            // Check if we have a collateral balance.
            (uint256 collateralBalance, ) = comet.userCollateral(account, info.asset);

            if (collateralBalance == 0) continue;

            // Get the value of collateral in USD.
            uint256 collateralPriceUsd = comet.getPrice(info.priceFeed);

            uint8 collateralDecimals = ERC20(info.asset).decimals();

            uint256 collateralValueInBase = collateralBalance.mulDivDown(collateralPriceUsd, 10 ** collateralDecimals);

            riskAdjustedCollateralValueInBase += collateralValueInBase.mulDivDown(info.liquidateCollateralFactor, 1e18);
        }

        return riskAdjustedCollateralValueInBase.mulDivDown(1e18, borrowBalance);
    }
}
