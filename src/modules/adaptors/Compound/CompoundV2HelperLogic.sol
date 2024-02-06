// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ComptrollerG7 as Comptroller, CErc20, PriceOracle } from "src/interfaces/external/ICompound.sol";
import { Test, stdStorage, StdStorage, stdError } from "lib/forge-std/src/Test.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @title CompoundV2 Helper Logic Contract Option A.
 * @notice Implements health factor logic used by both
 *         the CTokenAdaptorV2 && CompoundV2DebtAdaptor
 * @author crispymangoes, 0xEinCodes
 * NOTE: This version reduces some precision but helps simplify the health factor calculation by not using the `cToken.underlying.Decimals()` as a scalar throughout the health factor calculations. The 'lossy-ness' would amount to fractions of pennies when comparing the health factor calculations to the reported `getHypotheticalAccountLiquidityInternal()` results from CompoundV2 `getHypotheticalAccountLiquidityInternal()`. This is deemed negligible but needs to be proven via testing.
 * Option B, in `CompoundV2HelperLogicVersionB.sol` is the version of the health factor logic that follows CompoundV2's scaling factors used within the Comptroller.sol
 */
contract CompoundV2HelperLogic is Test {
    using Math for uint256;

    // vars to resolve stack too deep error
    // CErc20[] internal marketsEntered;

    /**
     @notice Compound action returned a non zero error code.
     */
    error CompoundV2HelperLogic__NonZeroCompoundErrorCode(uint256 errorCode);

    /**
     @notice Compound oracle returned a zero oracle value.
     @param asset that oracle query is associated to
     */
    error CompoundV2HelperLogic__OracleCannotBeZero(CErc20 asset);

    /**
     * @notice The ```_getHealthFactor``` function returns the current health factor
     */
    function _getHealthFactor(address _account, Comptroller comptroller) public view returns (uint256 healthFactor) {
        // get the array of markets currently being used
        CErc20[] memory marketsEntered;

        marketsEntered = comptroller.getAssetsIn(address(_account));
        PriceOracle oracle = comptroller.oracle();
        uint256 sumCollateral;
        uint256 sumBorrow;
        uint256 marketsEnteredLength = marketsEntered.length;
        // Loop to calculate total collateral & total borrow for HF calcs w/ assets we're in.
        for (uint256 i = 0; i < marketsEnteredLength; i++) {
            CErc20 asset = marketsEntered[i];
            // uint256 errorCode = asset.accrueInterest(); // TODO --> test if we need this by seeing if the exchange rates are 'kicked' when going through the rest of it. If so, remove this line of code.
            // if (errorCode != 0) revert CompoundV2HelperLogic__NonZeroCompoundErrorCode(errorCode);
            (uint256 oErr, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRate) = asset
                .getAccountSnapshot(_account);
            if (oErr != 0) revert CompoundV2HelperLogic__NonZeroCompoundErrorCode(oErr);
            uint256 oraclePrice = oracle.getUnderlyingPrice(asset);
            if (oraclePrice == 0) revert CompoundV2HelperLogic__OracleCannotBeZero(asset);
            // get collateral factor from markets
            (, uint256 collateralFactor, ) = comptroller.markets(address(asset)); // always scaled by 18 decimals
            uint256 actualCollateralBacking = cTokenBalance.mulDivDown(exchangeRate, 1e18); // NOTE - this is the 1st key difference usage of a different scaling factor than in OptionB and CompoundV2. This means less precision but it is possibly negligible.
            actualCollateralBacking = actualCollateralBacking.mulDivDown(oraclePrice, 1e18); // NOTE - this is the 2nd key difference usage of a different scaling factor than in OptionB and CompoundV2. This means less precision but it is possibly negligible.
            actualCollateralBacking = actualCollateralBacking.mulDivDown(collateralFactor, 1e18); // scaling factor for collateral factor is always 1e18.
            // scale up actualCollateralBacking to 1e18 if it isn't already for health factor calculations.
            uint256 additionalBorrowBalance = borrowBalance.mulDivDown(oraclePrice, 1e18); // converts cToken underlying borrow to USD
            sumCollateral = sumCollateral + actualCollateralBacking;
            sumBorrow = additionalBorrowBalance + sumBorrow;
        }
        // now we can calculate health factor with sumCollateral and sumBorrow
        healthFactor = sumCollateral.mulDivDown(1e18, sumBorrow);
    }
}
