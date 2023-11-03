// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { MorphoBlueHealthFactorLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHealthFactorLogic.sol";
import { IMorpho } from "src/interfaces/external/Morpho/Morpho Blue/IMorpho.sol";

/**
 * @title Morpho Blue Debt Token Adaptor
 * @notice Allows Cellars to borrow assets from Morpho Blue pairs.
 * @author crispymangoes, 0xEinCodes
 *  * TODO: THIS IS A WIP AND HAS LOTS OF TODOS AND REFERENCE TO FRAXLEND. THE STRATEGIST FUNCTIONS (NOT COMMENTED OUT) HAVE BASIC DIRECTION FOR MORPHO BLUE LENDING MARKETS

 */
contract MorphoDebtAdaptor is BaseAdaptor, MorphoBlueHealthFactorLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(MarketParams marketParams)
    // Where:
    // `marketParams` is the  struct this adaptor is working with.
    // TODO: Question for Morpho --> should we actually use `bytes32 Id` for the adaptorData?
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted to interact with an Morpho Blue Lending Market the Cellar is not using.
     */
    error MorphoBlueDebtAdaptor__MarketPositionsMustBeTracked(Id id);

    /**
     * @notice Attempted tx that results in unhealthy cellar
     */
    error MorphoBlueDebtAdaptor__HealthFactorTooLow(Id id);

    /**
     * @notice Attempted repayment when no debt position in Morpho Blue Lending Market for cellar
     */
    error MorphoBlueDebtAdaptor__CannotRepayNoDebt(Id id);

    /**
     * @notice The Morpho Blue contract on current network.
     */
    IMorpho public immutable morphoBlue;

    /**
     * @notice This bool determines how this adaptor accounts for interest.
     *         True: Account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     *         False: Do not account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     */
    bool public immutable ACCOUNT_FOR_INTEREST;

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(bool _accountForInterest, address _morphoBlue, uint256 _healthFactor) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        ACCOUNT_FOR_INTEREST = _accountForInterest;
        morphoBlue = IMorpho(_morphoBlue);
        minimumHealthFactor = _healthFactor;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Morpho Blue Debt Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position is a debt position, and user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellar's balance of the respective Fraxlend debtToken calculated from cellar borrow shares
     * @param adaptorData encoded fraxlendPair (fToken) for this position
     * TODO: EIN
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        MarketParams memory market = morphoBlue.idToMarketParams(_id);

        // IFToken fraxlendPair = abi.decode(adaptorData, (IFToken));
        // uint256 borrowShares = _userBorrowShares(fraxlendPair, msg.sender);
        // return _toBorrowAmount(fraxlendPair, borrowShares, false, ACCOUNT_FOR_INTEREST);
    }

    /**
     * @notice Returns `assetContract` from respective fraxlend pair, but this is most likely going to be FRAX.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        return ERC20(market.loanToken);
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================

    // `borrowAsset`
    /**
     * @notice Allows strategists to borrow assets from Morpho Blue.
     */
    function borrowFromMorphoBlue(Id id, uint256 amountToBorrow, uint256 shares) public {
        _validateMBMarket(id);
        MarketParams memory market = morphoBlue.idToMarketParams(id);
        _borrowAsset(market, amountToBorrow, shares, address(this));

        // // Check health factor is still satisfactory
        // // TODO: EIN
        // uint256 _exchangeRate = _getExchangeRateInfo(fraxlendPair);
        // // Check if borrower is insolvent after this borrow tx, revert if they are
        // if (minimumHealthFactor > (_getHealthFactor(fraxlendPair, _exchangeRate))) {
        //     revert DebtFTokenAdaptor__HealthFactorTooLow(address(fraxlendPair));
        // }
    }

    // `repayDebt`

    // /**
    //  * @notice Allows strategists to repay loan debt on Morph Blue Lending Market. Make sure to call addInterest() beforehand to ensure we are repaying what is required.
    //  * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
    //  * TODO: EIN
    //  */
    // function repayFraxlendDebt(IFToken _fraxlendPair, uint256 _debtTokenRepayAmount) public {
    //     _validateFToken(_fraxlendPair);
    //     ERC20 tokenToRepay = ERC20(_fraxlendPairAsset(_fraxlendPair));
    //     uint256 debtTokenToRepay = _maxAvailable(tokenToRepay, _debtTokenRepayAmount);
    //     uint256 sharesToRepay = _toBorrowShares(_fraxlendPair, debtTokenToRepay, false, true);
    //     uint256 sharesAccToFraxlend = _userBorrowShares(_fraxlendPair, address(this)); // get fraxlendPair's record of borrowShares atm
    //     if (sharesAccToFraxlend == 0) revert DebtFTokenAdaptor__CannotRepayNoDebt(address(_fraxlendPair)); // NOTE: from checking it out, unless `userBorrowShares[_borrower] -= _shares;` reverts, then fraxlendCore lets users repay FRAX w/ no limiters.

    //     // take the smaller btw sharesToRepay and sharesAccToFraxlend
    //     if (sharesAccToFraxlend < sharesToRepay) {
    //         sharesToRepay = sharesAccToFraxlend;
    //     }
    //     tokenToRepay.safeApprove(address(_fraxlendPair), type(uint256).max);

    //     _repayAsset(_fraxlendPair, sharesToRepay);

    //     _revokeExternalApproval(tokenToRepay, address(_fraxlendPair));
    // }

    /**
     * @notice Allows a strategist to call `addInterest` on a Frax Pair they are using.
     * @param _fraxlendPair The specified Fraxlend Pair
     * @dev A strategist might want to do this if a Frax Lend pair has not been interacted
     *      in a while, and the strategist does not plan on interacting with it during a
     *      rebalance.
     * @dev Calling this can increase the share price during the rebalance,
     *      so a strategist should consider moving some assets into reserves.
     */
    function callAddInterest(IFToken _fraxlendPair) public {
        _validateFToken(_fraxlendPair);
        _addInterest(_fraxlendPair);
    }

    /**
     * @notice Validates that a given Id is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateMBMarket(Id _id) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_id)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert MorphoBlueDebtAdaptor__MarketPositionsMustBeTracked(_id);
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // The Frax Pair interface can slightly change between versions.
    // To account for this, FTokenAdaptors (including debt and collateral adaptors) will use the below internal functions when
    // interacting with Frax Pairs, this way new pairs can be added by creating a
    // new contract that inherits from this one, and overrides any function it needs
    // so it conforms with the new Frax Pair interface.

    // Current versions in use for `Fraxlend Pair` include v1 and v2.

    // IMPORTANT: This `DebtFTokenAdaptor.sol` is associated to the v2 version of `Fraxlend Pair`
    // whereas DebtFTokenAdaptorV1 is actually associated to `FraxLendPairv1`.
    // The reasoning to name it like this was to set up the base DebtFTokenAdaptor for the
    // most current version, v2. This is in anticipation that more FraxLendPairs will
    // be deployed following v2 in the near future. When later versions are deployed,
    // then the described inheritance pattern above will be used.

    // NOTE: FraxlendHealthFactorLogic.sol has helper functions used for both v1 and v2 fraxlend pairs (`_getHealthFactor()`).
    // This function has a helper `_toBorrowAmount()` that corresponds to v2 by default, but is virtual and overwritten for
    // fraxlendV1 pairs as seen in Collateral and Debt adaptors for v1 pairs.
    //===============================================================================

    // /**
    //  * @notice Caller calls `addInterest` on specified 'v2' Fraxlend Pair
    //  * @dev fraxlendPair.addInterest() calls into the respective version (v2 by default) of Fraxlend Pair
    //  * @param fraxlendPair The specified Fraxlend Pair
    //  */
    // function _addInterest(IFToken fraxlendPair) internal virtual {
    //     fraxlendPair.addInterest(false);
    // }

    // /**
    //  * @notice Converts a given asset amount to a number of borrow shares from specified 'v2' Fraxlend Pair
    //  * @dev This is one of the adjusted functions from v1 to v2. ftoken.toBorrowAmount() calls into the respective version (v2 by default) of Fraxlend Pair
    //  * @param fToken The specified Fraxlend Pair
    //  * @param amount The amount of asset
    //  * @param roundUp Whether to round up after division
    //  * @param previewInterest Whether to preview interest accrual before calculation
    //  * @return number of borrow shares
    //  */
    // function _toBorrowShares(
    //     IFToken fToken,
    //     uint256 amount,
    //     bool roundUp,
    //     bool previewInterest
    // ) internal view virtual returns (uint256) {
    //     return fToken.toBorrowShares(amount, roundUp, previewInterest);
    // }

    /**
     * @notice Borrow amount of borrowAsset in cellar account within fraxlend pair
     * @param _borrowAmount The amount of borrowAsset to borrow
     * @param _fraxlendPair The specified Fraxlend Pair
     */
    function _borrowAsset(MarketParams _market, uint256 _assets, uint256 _shares, address _onBehalf) internal virtual {
        morphoBlue.borrow(_market, _assets, _shares, _onBehalf, address(this));
    }

    // /**
    //  * @notice Caller calls `updateExchangeRate()` on specified FraxlendV2 Pair
    //  * @param _fraxlendPair The specified FraxLendPair
    //  * @return exchangeRate needed to calculate the current health factor
    //  */
    // function _getExchangeRateInfo(IFToken _fraxlendPair) internal virtual returns (uint256 exchangeRate) {
    //     exchangeRate = _fraxlendPair.exchangeRateInfo().highExchangeRate;
    // }

    /**
     * @notice Repay Morpho Blue debt by an amount
     */
    function _repayAsset(MarketParams _market, uint256 _assets, uint256 _sharesToRepay, address _onBehalf) internal virtual {
        morphoBlue.repay(_market, _assets, _sharesToRepay, _onBehalf, bytes memory);
    }
}
