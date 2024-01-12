// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IComet } from "src/interfaces/external/Compound/IComet.sol";
// TODO remove
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

// TODO claim comp rewards?
contract V3Helper {
    using Math for uint256;

    // TODO Technically saying these prices are in USD is wrong, it is really in terms of the comets like virtual base, IE USD or ETH.
    function getAccountHealthFactor(IComet comet, address account) public view returns (uint256) {
        // Get the amount of base debt owed adjsuted for price.
        uint256 borrowBalanceInVirtualBase;
        {
            uint256 borrowBalanceInBase = comet.borrowBalanceOf(account);
            if (borrowBalanceInBase == 0) return type(uint256).max;
            uint8 baseDecimals = comet.baseToken().decimals();
            address basePriceFeed = comet.baseTokenPriceFeed();
            uint256 basePriceInVirtualBase = comet.getPrice(basePriceFeed);
            borrowBalanceInVirtualBase = borrowBalanceInBase.mulDivDown(basePriceInVirtualBase, 10 ** baseDecimals);
        }

        // TODO this for loop should have some reasonable upper bound, so that we are not gas griefed, and if exceeded, then we return a zero maybe?
        // So fixing this would require repaying all debt so borrow balance is zero, then  we will return above, so strategist can pull collateral.
        uint8 numberOfAssets = comet.numAssets();

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
