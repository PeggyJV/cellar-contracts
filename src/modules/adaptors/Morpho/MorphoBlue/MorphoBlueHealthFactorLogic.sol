// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// import { Math } from "src/utils/Math.sol";
import { IMorpho } from "src/interfaces/external/Morpho/Morpho Blue/IMorpho.sol";
import { MathLib, WAD } from "src/interfaces/external/Morpho/Morpho Blue/libraries/MathLib.sol";
import { SharesMathLib } from "src/interfaces/external/Morpho/Morpho Blue/libraries/SharesMathLib.sol";

/**
 * @title Morpho Blue Health Factor Logic contract.
 * @notice Implements health factor logic used by both
 *         the MorphoBlueCollateralAdaptor && MorphoBlueDebtAdaptor.
 * @author crispymangoes, 0xEinCodes
 * NOTE: helper functions made virtual in case future Morpho Blue Pair versions require different implementation logic.
 * NOTE: The library from Morpho provides exposed getters give cellar totalSupply and totalBorrow with interest accrued, although they are simulated values they have been tested compared to their actual Morpho Blue prod contract (within their test suite). This helper contract DOES NOT USE THE LIBRARIES FOR NOW and will try them during the testing phase of development. We will see if the libraries are more gas-efficient vs using getters. QUESTION FOR MORPHO TEAM - library for balances is usable and accurate to depend on. Do we want any failsafes just in case?
 */
contract MorphoBlueHealthFactorLogic {
    // using Math for uint256;
    type Id is bytes32; // NOTE not sure I need this

    // libraries from Morpho Blue codebase to ensure same mathematic methods for HF calcs
    using MathLib for uint128;
    using MathLib for uint256;
    using UtilsLib for uint256;
    using SharesMathLib for uint256;

    // Constant from MorphoBlue
    uint256 constant ORACLE_PRICE_SCALE = 1e36;

    constructor(addres _morphoBlue) {
        morphoBlue = IMorpho(_morphoBlue);
    }

    /**
     * @notice The ```_getHealthFactor``` function returns the current health factor of a respective position given an exchange rate
     * @param _id The specified Morpho Blue market Id
     * @return currentHF The health factor of the position atm
     */
    function _getHealthFactor(Id _id) internal view virtual returns (uint256) {
        uint256 borrowAmount = uint256(
            (morphoBlue.position(id, address(this)).borrowerShares).toAssetsUp(
                market(_id).totalBorrowAssets,
                market(_id).totalBorrowShares
            )
        ); // in delegateCall context - TODO -  make sure we get the tuple properly.
        if (borrowAmount == 0) return 1.05e18; // TODO - decide what to return in these scenarios.

        uint256 collateralAmount = uint256(
            (morphoBlue.position(_id)(address(this)).collateral).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE)
        ); // TODO -  make sure we get the tuple properly.
        if (collateralAmount == 0) return 0;

        // calculate the currentPositionLTV then compare it against the max lltv for this position
        // TODO check precision for all below.
        uint256 currentPositionLTV = borrowAmount.mulDivDown(1e18, _collateralAmount);
        uint256 positionMaxLTV = (marketParams.lltv) * collateralAmount;

        // convert LTVs to HF
        uint256 currentHF = positionMaxLTV.mulDivDown(1e18, currentPositionLTV);
    }
}
