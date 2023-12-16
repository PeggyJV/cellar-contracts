// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ComptrollerG7 as Comptroller, CErc20, PriceOracle } from "src/interfaces/external/ICompound.sol";
// import "lib/forge-std/src/console.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "lib/forge-std/src/Test.sol";

// import { console } from "lib/forge-std/src/Test.sol";

/**
 * @title CompoundV2 Helper Logic contract.
 * @notice Implements health factor logic used by both
 *         the CTokenAdaptorV2 && CompoundV2DebtAdaptor
 * @author crispymangoes, 0xEinCodes
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
     * TODO: fix decimals aspects in this
     */
    function _getHealthFactor(address _account, Comptroller comptroller) public view returns (uint256 healthFactor) {
        // Health Factor Calculations

        // get the array of markets currently being used
        CErc20[] memory marketsEntered = comptroller.getAssetsIn(address(_account));

        PriceOracle oracle = comptroller.oracle();
        uint256 sumCollateral;
        uint256 sumBorrow;
        console.log("Oracle, also setting console.log: %s", address(oracle));

        for (uint256 i = 0; i < marketsEntered.length; i++) {
            CErc20 asset = marketsEntered[i];
            // call accrueInterest() to update exchange rates before going through the loop --> TODO --> test if we need this by seeing if the exchange rates are 'kicked' when going through the rest of it. If so, remove this line of code.
            // uint256 errorCode = asset.accrueInterest(); // TODO: resolve error about potentially modifying state
            // if (errorCode != 0) revert CompoundV2HelperLogic__NonZeroCompoundErrorCode(errorCode);

            // TODO We're going through a loop to calculate total collateral & total borrow for HF calcs (Starting below) w/ assets we're in.
            (uint256 oErr, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRateMantissa) = asset
                .getAccountSnapshot(_account);
            if (oErr != 0) revert CompoundV2HelperLogic__NonZeroCompoundErrorCode(oErr);
            console.log(
                "oErr: %s, cTokenBalance: %s, borrowBalance: %s, exchangeRateMantissa: %s",
                oErr,
                cTokenBalance,
                borrowBalance,
                exchangeRateMantissa
            );

            // get collateral factor from markets
            (, uint256 collateralFactor, ) = comptroller.markets(address(asset));
            console.log("CollateralFactor: %s", collateralFactor);

            // TODO console.log to see what the values look like (decimals, etc.)

            // TODO Then normalize the values and get the HF with them. If it's safe, then we're good, if not revert.
            uint256 oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            console.log("oraclePriceMantissa: %s", oraclePriceMantissa);

            if (oraclePriceMantissa == 0) revert CompoundV2HelperLogic__OracleCannotBeZero(asset);

            // TODO: possibly convert oraclePriceMantissa to Exp format (like compound where it is 18 decimals representation)
            uint256 tokensToDenom = (collateralFactor * exchangeRateMantissa) * oraclePriceMantissa; // TODO: make this 18 decimals --> units are underlying/cToken *
            console.log("tokensToDenom: %s", tokensToDenom);

            // What are the units of exchangeRate, oraclePrice, tokensToDenom? Is it underlying/cToken, usd/underlying, usd/cToken, respectively?
            sumCollateral = (tokensToDenom * cTokenBalance) + sumCollateral; // Units --> usd/CToken * cToken --> equates to usd
            console.log("sumCollateral: %s", sumCollateral);

            sumBorrow = (oraclePriceMantissa * borrowBalance) + sumBorrow; // Units --> usd/underlying * underlying --> equates to usd
            console.log("sumBorrow: %s", sumBorrow);
        }

        // now we can calculate health factor with sumCollateral and sumBorrow
        healthFactor = sumCollateral / sumBorrow;
    }
}
