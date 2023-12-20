// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ComptrollerG7 as Comptroller, CErc20, PriceOracle } from "src/interfaces/external/ICompound.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "lib/forge-std/src/Test.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Math } from "src/utils/Math.sol";
// import { console } from "lib/forge-std/src/Test.sol";

/**
 * @title CompoundV2 Helper Logic Contract Option B.
 * @notice Implements health factor logic used by both
 *         the CTokenAdaptorV2 && CompoundV2DebtAdaptor
 * @author crispymangoes, 0xEinCodes
 * NOTE: This is the version of the health factor logic that follows CompoundV2's scaling factors used within the Comptroller.sol `getHypotheticalAccountLiquidityInternal()`. The other version of, "Option A," reduces some precision but helps simplify the health factor calculation by not using the `cToken.underlying.Decimals()` as a scalar throughout the health factor calculations. Instead Option A uses 10^18 throughout. The 'lossy-ness' would amount to fractions of pennies when comparing the health factor calculations to the reported `getHypotheticalAccountLiquidityInternal()` results from CompoundV2. This is deemed negligible but needs to be proven via testing.
 * TODO - debug stack too deep errors arising when running `forge build`
 * TODO - write test to see if the lossy-ness is negligible or not versus using `CompoundV2HelperLogicVersionA.sol` 
 */
contract CompoundV2HelperLogic_VersionB is Test {
    using Math for uint256;

    // vars to resolve stack too deep error
    CErc20[] internal marketsEntered;

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
     * TODO: Decimals aspect is to be figured out in github PR #167 comments
     */
    function _getHealthFactor(address _account, Comptroller comptroller) public view returns (uint256 healthFactor) {
        // get the array of markets currently being used
        marketsEntered = comptroller.getAssetsIn(address(_account));

        PriceOracle oracle = comptroller.oracle();
        uint256 sumCollateral;
        uint256 sumBorrow;

        // Loop to calculate total collateral & total borrow for HF calcs w/ assets we're in.
        for (uint256 i = 0; i < marketsEntered.length; i++) {
            CErc20 asset = marketsEntered[i];

            // uint256 errorCode = asset.accrueInterest(); // TODO --> test if we need this by seeing if the exchange rates are 'kicked' when going through the rest of it. If so, remove this line of code.
            // if (errorCode != 0) revert CompoundV2HelperLogic__NonZeroCompoundErrorCode(errorCode);

            (uint256 oErr, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRate) = asset
                .getAccountSnapshot(_account);
            if (oErr != 0) revert CompoundV2HelperLogic__NonZeroCompoundErrorCode(oErr);

            uint256 oraclePrice = oracle.getUnderlyingPrice(asset);
            if (oraclePrice == 0) revert CompoundV2HelperLogic__OracleCannotBeZero(asset);

            ERC20 underlyingAsset = ERC20(asset.underlying());
            uint256 underlyingDecimals = underlyingAsset.decimals();

            // calculate scaling factors of compound oracle prices & exchangeRate
            uint256 oraclePriceScalingFactor = 36 - underlyingDecimals;
            uint256 exchangeRateScalingFactor = 18 - 8 + underlyingDecimals; //18 - 8 + underlyingDecimals

            // get collateral factor from markets
            (, uint256 collateralFactor, ) = comptroller.markets(address(asset)); // always scaled by 18 decimals

            uint256 actualCollateralBacking = cTokenBalance.mulDivDown(exchangeRate, 10 ** (exchangeRateScalingFactor)); // Now in terms of underlying asset decimals. --> 8 + 28 - 18 = 18 decimals --> for usdc we need it to be 6... let's see. 8 + 16 - 16. OK so that would get us 8 decimals. nice.

            actualCollateralBacking = actualCollateralBacking.mulDivDown(oraclePrice, oraclePriceScalingFactor); // converts it to USD but it is in the decimals of the underlying.

            actualCollateralBacking = actualCollateralBacking.mulDivDown(collateralFactor, 1e18); // scaling factor for collateral factor is always 1e18.

            // scale up actualCollateralBacking to 1e18 if it isn't already.

            uint256 additionalBorrowBalance = borrowBalance.mulDivDown(oraclePrice, oraclePriceScalingFactor); // converts cToken underlying borrow to USD but it's in decimals of underlyingAsset

            // scale up additionalBorrowBalance to 1e18 if it isn't already.
            _refactorBalance(additionalBorrowBalance, underlyingDecimals);
            _refactorBalance(actualCollateralBacking, underlyingDecimals);

            sumCollateral = sumCollateral + actualCollateralBacking;

            sumBorrow = borrowBalance.mulDivDown(oraclePrice, oraclePriceScalingFactor) + sumBorrow;
        }

        // now we can calculate health factor with sumCollateral and sumBorrow
        healthFactor = sumCollateral.mulDivDown(1e18, sumBorrow); // TODO: figure out the scaling factor for health factor
        console.log("healthFactor: %s", healthFactor);
    }

    // helper that scales passed in param _balance to 18 decimals. This is needed to make it easier for health factor calculations
    function _refactorBalance(uint256 _balance, uint256 _decimals) public pure returns (uint256) {
        if (_decimals != 18) {
            _balance = _balance * (10 ** (18 - _decimals));
        }
        return _balance;
    }
}
