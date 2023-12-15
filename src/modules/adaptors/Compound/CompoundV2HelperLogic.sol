// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompoundV2.sol";

/**
 * @title CompoundV2 Helper Logic contract.
 * @notice Implements health factor logic used by both
 *         the CTokenAdaptorV2 && CompoundV2DebtAdaptor
 * @author crispymangoes, 0xEinCodes
 */
contract CompoundV2HelperLogic {
    using Math for uint256;

    /**
     * @notice The ```_getHealthFactor``` function returns the current health factor
     * TODO:
     */
    function _getHealthFactor() public {
        // Health Factor Calculations
        // TODO to get a users health factor, I think we can call `comptroller.getAssetsIn` to get the array of markets currently being used
        // TODO grab oracle from comptroller
        // TODO call accrueInterest() to update exchange rates before going through the loop --> TODO --> test if we need this by seeing if the exchange rates are 'kicked' when going through the rest of it. If so, remove this line of code.
        // TODO We're going through a loop to calculate total collateral & total borrow for HF calcs (Starting below) w// assets we're in.
        // TODO Within each asset:
        // TODO             `(oErr, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account);``
        // TODO grab collateral factors -->             vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
        // TODO Then normalize the values and get the HF with them. If it's safe, then we're good, if not revert.
        // As collateral, then we can use the price router to get a dollar value of the collateral. Although Compound stouts they have their own pricing too (based off of chainlink)
    }
}
