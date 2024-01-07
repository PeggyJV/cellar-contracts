// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// import { Math } from "src/utils/Math.sol";
import { IMorpho, MarketParams, Market, Id } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { MathLib, WAD } from "src/interfaces/external/Morpho/MorphoBlue/libraries/MathLib.sol";
import { SharesMathLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/SharesMathLib.sol";
import { IOracle } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IOracle.sol";
import { UtilsLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/UtilsLib.sol";
import { MorphoLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/periphery/MorphoLib.sol";
import { console } from "@forge-std/Test.sol";

/**
 * @title Morpho Blue Health Factor Logic contract.
 * @notice Implements health factor logic used by both
 *         the MorphoBlueCollateralAdaptor && MorphoBlueDebtAdaptor.
 * @author 0xEinCodes, crispymangoes
 * NOTE: helper functions made virtual in case future Morpho Blue Pair versions require different implementation logic.
 */
contract MorphoBlueHealthFactorLogic {
    // libraries from Morpho Blue codebase to ensure same mathematic methods for HF calcs
    using MathLib for uint128;
    using MathLib for uint256;
    using UtilsLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;

    /**
     * @notice The Morpho Blue contract on current network.
     */
    IMorpho public immutable morphoBlue;

    // Constant from MorphoBlue
    uint256 constant ORACLE_PRICE_SCALE = 1e36;

    constructor(address _morphoBlue) {
        morphoBlue = IMorpho(_morphoBlue);
    }

    /**
     * @notice The ```_getHealthFactor``` function returns the current health factor of a respective position given an exchange rate
     * @param _id The specified Morpho Blue market Id
     * @param _market The specified Morpho Blue market
     * @return currentHF The health factor of the position atm
     */
    function _getHealthFactor(Id _id, MarketParams memory _market) internal view virtual returns (uint256 currentHF) {
        uint256 borrowAmount = _userBorrowBalance(_id, address(this));
        console.log("borrowAmount: %s", borrowAmount);
        if (borrowAmount == 0) return type(uint256).max;

        uint256 collateralPrice = IOracle(_market.oracle).price(); // recall from IOracle.sol that the units will be 10 ** (36 - collateralUnits + borrowUnits) BUT collateralPrice is in units of borrow.

        // get collateralAmount in borrowAmount for LTV calculations
        uint256 collateralAmount = _userCollateralBalance(_id, address(this));
        console.log(
            "userCollateralBalance: %s, collateralPrice: %s, collateralAmount: %s",
            _userCollateralBalance(_id, address(this)),
            collateralPrice,
            collateralAmount
        );
        uint256 collateralAmountInBorrowUnits = collateralAmount.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE); // typecasting uint256 not sure if needed.

        if (collateralAmountInBorrowUnits == 0) return 0;

        // calculate the currentPositionLTV then compare it against the max lltv for this position
        uint256 LTV_PRECISION = 1e18;
        uint256 currentPositionLTV = borrowAmount.mulDivUp(LTV_PRECISION, collateralAmountInBorrowUnits);

        console.log(
            "positionMaxLTV: %s, currentPositionLTV: %s, collateralAmountInBorrowUnits: %s",
            _market.lltv,
            currentPositionLTV,
            collateralAmountInBorrowUnits
        );
        // convert LTVs to HF
        currentHF = (_market.lltv).mulDivDown(1e18, currentPositionLTV);
    }

    /**
     * @dev helper function that returns actual supply position amount for caller according to MB market accounting. This is alternative to using the MB periphery libraries that simulate accrued interest balances.
     * NOTE: make sure to call `accrueInterest()` on respective market before calling these helpers
     */
    function _userSupplyBalance(Id _id, address _user) internal view returns (uint256) {
        Market memory market = morphoBlue.market(_id);
        // this currently doesn't account for interest, that needs to be done before calling this helper.
        return (morphoBlue.supplyShares(_id, _user).toAssetsDown(market.totalSupplyAssets, market.totalSupplyShares));
    }

    /**
     * @dev helper function that returns actual collateral position amount for caller according to MB market accounting. This is alternative to using the MB periphery libraries that simulate accrued interest balances.
     * NOTE: make sure to call `accrueInterest()` on respective market before calling these helpers
     */
    function _userCollateralBalance(Id _id, address _user) internal view virtual returns (uint256) {
        // return uint256(morphoBlue.position(_id, address(this)).collateral);
        return morphoBlue.collateral(_id, _user);
    }

    /**
     * @dev helper function that returns actual borrow position amount for caller according to MB market accounting. This is alternative to using the MB periphery libraries that simulate accrued interest balances.
     * NOTE: make sure to call `accrueInterest()` on respective market before calling these helpers
     */
    function _userBorrowBalance(Id _id, address _user) internal view returns (uint256) {
        Market memory market = morphoBlue.market(_id);
        return (
            uint256((morphoBlue.position(_id, _user).borrowShares)).toAssetsUp(
                market.totalBorrowAssets,
                market.totalBorrowShares
            )
        );
    }

    /**
     * @notice Caller calls `accrueInterest` on specified MB market
     * @param _market The specified MB market
     */
    function _accrueInterest(MarketParams memory _market) internal virtual {
        morphoBlue.accrueInterest(_market);
    }
}
