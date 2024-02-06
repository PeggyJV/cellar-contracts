// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ComptrollerG7 as Comptroller, CErc20, PriceOracle } from "src/interfaces/external/ICompound.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "lib/forge-std/src/Test.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Math } from "src/utils/Math.sol";

import { console } from "lib/forge-std/src/Test.sol";

/**
 * @title CompoundV2 Helper Logic Contract Option B.
 * @notice Implements health factor logic used by both
 *         the CTokenAdaptorV2 && CompoundV2DebtAdaptor
 * @author crispymangoes, 0xEinCodes
 * NOTE: This is the version of the health factor logic that follows CompoundV2's scaling factors used within the Comptroller.sol `getHypotheticalAccountLiquidityInternal()`. The other version of, "Option A," reduces some precision but helps simplify the health factor calculation by not using the `cToken.underlying.Decimals()` as a scalar throughout the health factor calculations. Instead Option A uses 10^18 throughout. The 'lossy-ness' would amount to fractions of pennies when comparing the health factor calculations to the reported `getHypotheticalAccountLiquidityInternal()` results from CompoundV2. This is deemed negligible but needs to be proven via testing.
 * TODO - debug stack too deep errors arising when running `forge build`
 * TODO - write test to see if the lossy-ness is negligible or not versus using `CompoundV2HelperLogicVersionA.sol`
 */
contract CompoundV2HelperLogic is Test {
    using Math for uint256;

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
        // Loop to calculate total collateral & total borrow for HF calcs w/ assets we're in.
        for (uint256 i = 0; i < marketsEntered.length; i++) {
            // Obtain values from markets
            CErc20 asset = marketsEntered[i];
            (uint256 oErr, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRate) = asset
                .getAccountSnapshot(_account);
            if (oErr != 0) revert CompoundV2HelperLogic__NonZeroCompoundErrorCode(oErr);
            uint256 oraclePrice = oracle.getUnderlyingPrice(asset);
            if (oraclePrice == 0) revert CompoundV2HelperLogic__OracleCannotBeZero(asset);
            ERC20 underlyingAsset = ERC20(asset.underlying());
            uint256 underlyingDecimals = underlyingAsset.decimals();

            // Actual calculation of collateral and borrows for respective markets.
            // NOTE - below is scoped for stack too deep errors
            {
                (, uint256 collateralFactor, ) = comptroller.markets(address(asset)); // get collateral factor from markets
                uint256 oraclePriceScalingFactor = 10 ** (36 - underlyingDecimals);
                uint256 exchangeRateScalingFactor = 10 ** (18 - 8 + underlyingDecimals); //18 - 8 + underlyingDecimals
                uint256 actualCollateralBacking = cTokenBalance.mulDivDown(exchangeRate, exchangeRateScalingFactor); // Now in terms of underlying asset decimals. --> 8 + 30 - 16 = 22 decimals --> for usdc we need it to be 6... let's see. 8 + 16 - 16. OK so that would get us 8 decimals. oh that's not right.
                // 8 + 16 - 16 --> ends up w/ 8 decimals. hmm.
                // okay, for dai, you'd end up with: 8 + 28 - 28... yeah so it just stays as 8
                console.log(
                    "oraclePrice: %s, oraclePriceScalingFactor, %s, collateralFactor: %s",
                    oraclePrice,
                    oraclePriceScalingFactor,
                    collateralFactor
                );
                console.log(
                    "actualCollateralBacking1 - before oraclePrice, oracleFactor, collateralFactor: %s",
                    actualCollateralBacking
                );

                // convert to USD values
                console.log("actualCollateralBacking_BeforeOraclePrice: %s", actualCollateralBacking);

                actualCollateralBacking = actualCollateralBacking.mulDivDown(oraclePrice, oraclePriceScalingFactor); // converts it to USD but it is in the decimals of the underlying --> it's still in decimals of 8 (so ctoken decimals)
                console.log("actualCollateralBacking_AfterOraclePrice: %s", actualCollateralBacking);

                // Apply collateral factor to collateral backing
                actualCollateralBacking = actualCollateralBacking.mulDivDown(collateralFactor, 1e18); // scaling factor for collateral factor is always 1e18.

                console.log("actualCollateralBacking_BeforeRefactor: %s", actualCollateralBacking);

                // refactor as needed for decimals
                actualCollateralBacking = _refactorCollateralBalance(actualCollateralBacking, underlyingDecimals); // scale up additionalBorrowBalance to 1e18 if it isn't already.

                // borrow balances
                // NOTE - below is scoped for stack too deep errors
                {
                    console.log("additionalBorrowBalanceA: %s", borrowBalance);

                    uint256 additionalBorrowBalance = borrowBalance.mulDivDown(oraclePrice, oraclePriceScalingFactor); // converts cToken underlying borrow to USD but it's in decimals of underlyingAsset
                    console.log("additionalBorrowBalanceBeforeRefactor: %s", additionalBorrowBalance);

                    // refactor as needed for decimals
                    additionalBorrowBalance = _refactorBorrowBalance(additionalBorrowBalance, underlyingDecimals);

                    sumBorrow = sumBorrow + additionalBorrowBalance;
                    console.log("additionalBorrowBalanceAfterRefactor: %s", additionalBorrowBalance);
                }

                sumCollateral = sumCollateral + actualCollateralBacking;
                console.log("actualCollateralBacking_AfterRefactor: %s", actualCollateralBacking);
            }
        }
        // now we can calculate health factor with sumCollateral and sumBorrow
        healthFactor = sumCollateral.mulDivDown(1e18, sumBorrow);
        console.log("healthFactor: %s", healthFactor);
    }

    // helper that scales passed in param _balance to 18 decimals. _balance param is always passed in 8 decimals (cToken decimals). This is needed to make it easier for health factor calculations
    function _refactorCollateralBalance(uint256 _balance, uint256 _decimals) public view returns (uint256 balance) {
        uint256 balance = _balance;
        if (_decimals < 8) {
            //convert to _decimals precision first)
            balance = _balance / (10 ** (8 - _decimals));
        } else if (_decimals > 8) {
            balance = _balance * (10 ** (_decimals - 8));
        }
        console.log("EIN THIS IS THE FIRST REFACTORED COLLAT BALANCE: %s", balance);
        if (_decimals != 18) {
            balance = balance * (10 ** (18 - _decimals)); // if _balance is 8 decimals, it'll convert balance to 18 decimals. Ah.
        }
        return balance;
    }

    function _refactorBorrowBalance(uint256 _balance, uint256 _decimals) public view returns (uint256 balance) {
        uint256 balance = _balance;
        if (_decimals != 18) {
            balance = balance * (10 ** (18 - _decimals)); // if _balance is 8 decimals, it'll convert balance to 18 decimals. Ah.
        }
        return balance;
    }
}
