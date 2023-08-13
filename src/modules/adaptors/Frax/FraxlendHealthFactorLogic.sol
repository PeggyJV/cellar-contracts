// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";

/**
 * @title Fraxlend Health Factor Logic contract.
 * @notice Implements health factor logic used by both
 *         the CollateralFTokenAdaptor && DebtFTokenAdaptor.
 * @author crispymangoes, 0xEinCodes
 * NOTE: helper functions made virtual in case future Fraxlend Pair versions require different implementation logic. The logic here is written in compliance with FraxlendV2; specifically the helper `_toBorrowAmount()`
 */
contract FraxlendHealthFactorLogic {
    using Math for uint256;

    /// @notice The ```_isSolvent``` function returns the current health factor of a respective position given an exchange rate
    /// @param _exchangeRate The exchange rate, i.e. the amount of collateral to buy 1e18 asset
    /// @return current health factor to compare against minimum health factor
    /// @dev NOTE: TODO: Do we need further tests comparing the `_isSolvent` calcs in Fraxlend so we are calculating the same thing at all times.
    function _isSolvent(IFToken _fraxlendPair, uint256 _exchangeRate) internal view virtual returns (uint256) {
        // calculate the borrowShares
        uint256 borrowerShares = _fraxlendPair.userBorrowShares(address(this));
        uint256 _borrowerAmount = _toBorrowAmount(_fraxlendPair, borrowerShares, true, true); // need interest-adjusted and conservative amount (round-up) similar to `_isSolvent()` function in actual Fraxlend contracts.
        if (_borrowerAmount == 0) return 1.05e18; // TODO: CRISPY is this the best way to go about returning on _borrowerAmount == 0?
        uint256 _collateralAmount = _fraxlendPair.userCollateralBalance(address(this));
        if (_collateralAmount == 0) return 0; // TODO: CRISPY is this the best way to go about returning on _collateralAmount == 0?

        (uint256 LTV_PRECISION, , , , uint256 EXCHANGE_PRECISION, , , ) = _fraxlendPair.getConstants();

        uint256 currentPositionLTV = (((_borrowerAmount * _exchangeRate) / EXCHANGE_PRECISION) * LTV_PRECISION) /
            _collateralAmount;

        // get maxLTV from fraxlendPair
        uint256 fraxlendPairMaxLTV = _fraxlendPair.maxLTV();

        // convert LTVs to HF
        uint256 currentHF = fraxlendPairMaxLTV.mulDivDown(1e18, currentPositionLTV);

        // compare HF to current HF.
        return currentHF;
    }

    /**
     * @notice Converts a given number of borrow shares to debtToken amount from specified 'v2' FraxLendPair
     * @dev This is one of the adjusted functions from v1 to v2. fraxlendPair.toBorrowAmount() calls into the respective version (v2 by default) of FraxLendPair
     * @param _fraxlendPair The specified FraxLendPair
     * @param _shares Shares of debtToken
     * @param _roundUp Whether to round up after division
     * @param _previewInterest Whether to preview interest accrual before calculation
     */
    function _toBorrowAmount(
        IFToken _fraxlendPair,
        uint256 _shares,
        bool _roundUp,
        bool _previewInterest
    ) internal view virtual returns (uint256) {
        return _fraxlendPair.toBorrowAmount(_shares, _roundUp, _previewInterest);
    }
}
