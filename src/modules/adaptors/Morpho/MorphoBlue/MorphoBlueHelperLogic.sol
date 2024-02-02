// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IMorpho, MarketParams, Market, Id } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { MathLib, WAD } from "src/interfaces/external/Morpho/MorphoBlue/libraries/MathLib.sol";
import { SharesMathLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/SharesMathLib.sol";
import { IOracle } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IOracle.sol";
import { UtilsLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/UtilsLib.sol";
import { MorphoLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/periphery/MorphoLib.sol";
import { Cellar } from "src/modules/adaptors/BaseAdaptor.sol";

/**
 * @title Morpho Blue Helper contract.
 * @notice Helper implementation including health factor logic used by Morpho Blue Adaptors.
 * @author 0xEinCodes, crispymangoes
 * NOTE: helper functions made virtual in case future Morpho Blue Pair versions require different implementation logic.
 */
contract MorphoBlueHelperLogic {
    // Using libraries from Morpho Blue codebase to ensure same mathematic methods
    using MathLib for uint128;
    using MathLib for uint256;
    using UtilsLib for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;

    /**
     * @notice Attempted to interact with an Morpho Blue Lending Market the Cellar is not using.
     */
    error MorphoBlueAdaptors__MarketPositionsMustBeTracked(MarketParams market);

    /**
     * @notice The Morpho Blue contract on current network.
     */
    IMorpho public immutable morphoBlue;

    // Constant from Morpho Blue
    uint256 constant ORACLE_PRICE_SCALE = 1e36;

    constructor(address _morphoBlue) {
        morphoBlue = IMorpho(_morphoBlue);
    }

    /**
     * @notice The ```_getHealthFactor``` function returns the current health factor of a respective position given an exchange rate.
     * @param _id The specified Morpho Blue market Id.
     * @param _market The specified Morpho Blue market.
     * @return currentHF The health factor of the position atm.
     */
    function _getHealthFactor(Id _id, MarketParams memory _market) internal view virtual returns (uint256 currentHF) {
        uint256 borrowAmount = _userBorrowBalance(_id, address(this));
        if (borrowAmount == 0) return type(uint256).max;
        uint256 collateralPrice = IOracle(_market.oracle).price(); // recall from IOracle.sol that the units will be 10 ** (36 - collateralUnits + borrowUnits) BUT collateralPrice is in units of borrow.

        // get collateralAmount in borrowAmount for LTV calculations
        uint256 collateralAmount = _userCollateralBalance(_id, address(this));
        uint256 collateralAmountInBorrowUnits = collateralAmount.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
        currentHF = _market.lltv.mulDivDown(collateralAmountInBorrowUnits, borrowAmount);
    }

    /**
     * @dev helper function that returns actual supply position amount for specified `_user` according to MB market accounting. This is alternative to using the MB periphery libraries that simulate accrued interest balances.
     * @param _id identifier of a Morpho Blue market.
     * @param _user address that this function will query Morpho Blue market for.
     * @return Actual supply amount for the `_user`
     * NOTE: make sure to call `accrueInterest()` on respective market before calling these helpers.
     */
    function _userSupplyBalance(Id _id, address _user) internal view returns (uint256) {
        Market memory market = morphoBlue.market(_id);
        return (morphoBlue.supplyShares(_id, _user).toAssetsDown(market.totalSupplyAssets, market.totalSupplyShares));
    }

    /**
     * @dev helper function that returns actual supply position shares amount for specified `_user` according to MB market accounting.
     * @param _id identifier of a Morpho Blue market.
     * @param _user address that this function will query Morpho Blue market for.
     * @return Actual supply share amount for the `_user`
     */
    function _userSupplyShareBalance(Id _id, address _user) internal view returns (uint256) {
        return (morphoBlue.supplyShares(_id, _user));
    }

    /**
     * @dev helper function that returns actual collateral position amount for specified `_user` according to MB market accounting.
     */
    function _userCollateralBalance(Id _id, address _user) internal view virtual returns (uint256) {
        return morphoBlue.collateral(_id, _user);
    }

    /**
     * @dev helper function that returns actual borrow position amount for specified `_user` according to MB market accounting. This is alternative to using the MB periphery libraries that simulate accrued interest balances.
     * @param _id identifier of a Morpho Blue market.
     * @param _user address that this function will query Morpho Blue market for.
     * NOTE: make sure to call `accrueInterest()` on respective market before calling these helpers.
     */
    function _userBorrowBalance(Id _id, address _user) internal view returns (uint256) {
        Market memory market = morphoBlue.market(_id);
        return morphoBlue.borrowShares(_id, _user).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
    }

    /**
     * @notice Allows a strategist to call `accrueInterest()` on a MB Market that the cellar is using.
     * @dev A strategist might want to do this if a MB market has not been interacted with
     *      in a while, and the strategist does not plan on interacting with it during a
     *      rebalance.
     * @dev Calling this can increase the share price during the rebalance,
     *      so a strategist should consider moving some assets into reserves.
     * @param _market identifier of a Morpho Blue market.
     */
    function accrueInterest(MarketParams memory _market) public {
        morphoBlue.accrueInterest(_market);
    }

    /**
     * @notice Validates that a given market is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     * @param _market MarketParams struct for a specific Morpho Blue market.
     * @param _identifier Identifier unique to an adaptor for a shared registry.
     * @param _isDebt Whether or not the respective position is a debt position.
     */
    function _validateMBMarket(MarketParams memory _market, bytes32 _identifier, bool _isDebt) internal view {
        bytes32 positionHash = keccak256(abi.encode(_identifier, _isDebt, abi.encode(_market)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert MorphoBlueAdaptors__MarketPositionsMustBeTracked(_market);
    }
}
