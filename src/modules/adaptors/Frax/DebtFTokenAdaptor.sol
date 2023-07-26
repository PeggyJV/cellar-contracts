// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";

/**
 * @title FraxLend Debt Token Adaptor
 * @notice Allows Cellars to borrow assets from FraxLend pairs.
 * @author crispymangoes, 0xEinCodes
 * TODO: remove this when done -> NOTE: toAssetAmount() has 3 vars in newest version, in older version it only has two.
 */
contract DebtFTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    //
    // adaptorData = abi.encode(address fToken)
    // Where:
    // `fToken` is the fToken address associated to the fraxlend pair this adaptor position is working with.
    //================= Configuration Data Specification =================
    //
    //====================================================================

    /**
     * @notice Attempted to interact with an fToken the Cellar is not using.
     */
    error DebtFTokenAdaptor__FTokenPositionsMustBeTracked(address fToken);

    /**
     * @notice Attempted tx that results in unhealthy cellar LTV
     */
    error DebtFTokenAdaptor__LTVTooLow(address fToken);

    /**
     * @notice Fraxlend Pair contract reporting higher repayment amount than Strategist is comfortable with according to Strategist params.
     * @dev TODO: see notes for function involved. This may not be needed.
     */
    error DebtFTokenAdaptor__AmountOwingExceedsSpecifiedRepaymentMax(address fToken);

    /**
     * @notice Unexpected result in borrow shares within fraxlend pair after repayment
     * TODO: not sure if we want it like this, this basically blocks repayments if the accounting is different btw this adaptor and the fraxlend pair.
     */
    error DebtFTokenAdaptor__RepaymentShareAmountDecrementedIncorrectly(address fToken);

    /**
     * @notice This bool determines how this adaptor accounts for interest.
     *         True: Account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     *         False: Do not account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     * TODO: I think we need this, but need to double check for lending/borrowing setup in Fraxlend.
     */
    bool public immutable ACCOUNT_FOR_INTEREST;

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
     * TODO: This was from AaveDebtTokenAdaptor. IMO this is unecessary since Fraxlend has its own immutable LTV value. That said, we can have this as an extra safety measure if we really want. I think that it would lean on the LTV getter from FraxlendPair, and then it would check it against the minimum value in here. Whichever is more conservative, it goes with.
     */
    uint256 public immutable minimumHealthFactor;

    /**
     * @notice The FRAX contract on current network.
     * @notice For mainnet use 0x853d955aCEf822Db058eb8505911ED77F175b99e.
     */
    ERC20 public immutable FRAX;

    constructor(bool _accountForInterest, address _frax) {
        ACCOUNT_FOR_INTEREST = _accountForInterest; //TODO: I think we need this, but need to double check for lending/borrowing setup in Fraxlend.
        FRAX = ERC20(_frax);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("FraxLend debtToken Adaptor V 1.0"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
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
     * @param adaptorData encoded fToken (fraxlendPair) for this position
     * TODO: CRISPY QUESTION - should we call them fTokens, or fraxlendPairs? I've gone ahead and made them fTokens to stay consistent, but it could be argued that for lending/borrowing it makes more sense to specify it as FraxlendPair.
     * TODO: CRISPY QUESTION - From looking at AaveDebtTokenAdaptor balanceOf() it looks like it just reports the amount of debtTokens it has, not the overall owed amount? As in, if the cellar borrowed a bunch of DAI from Aave, and then used it, it wouldn't account for it anymore. Need to think on this more. I'd think we need to show the amount of debt that this cellar has/is accruing (thus account for interest would be set to true).
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        return _toBorrowAmount(fToken, fToken.userBorrowShares(msg.sender), false, ACCOUNT_FOR_INTEREST);
    }

    /**
     * @notice Returns FRAX.
     */
    function assetOf(bytes memory) public view override returns (ERC20) {
        return FRAX;
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
     * @notice Allows strategists to borrow assets from Fraxlend.
     * @notice `debtTokenToBorrow` must be the debtToken, NOT the underlying ERC20.
     * @param fToken the Fraxlend Pair to borrow from.
     * @param amountToBorrow the amount of `debtTokenToBorrow` to borrow on Fraxlend.
     * NOTE: `borrowAsset` is the same btw v1 and v2 FraxlendPairs
     * TODO: See helper `_isSolvent` --> NOTE that it is the same helper in CollateralFTokenAdaptor, so once either is figured out just copy and paste the proper solution.
     */
    function borrowFromFraxlend(IFToken fToken, uint256 amountToBorrow) public {
        // Check that debt position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(address(fToken))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert DebtFTokenAdaptor__FTokenPositionsMustBeTracked(address(fToken));

        fToken.borrowAsset(amountToBorrow, 0, msg.sender); // TODO: CRISPY - Could have second param, `_collateralAmount` nonzero by having Strategist specify an amount if they want to top up their position or not.

        // Check LTV is still satisfactory
        (, uint256 _exchangeRate, ) = fToken._updateExchangeRate(); // needed to calculate LTV in next line
        // Check if borrower is insolvent after this borrow tx, revert if they are
        if (!_isSolvent(address(this), _exchangeRate)) {
            revert DebtFTokenAdaptor__LTVTooLow(address(fToken));
        }
    }

    // `repayDebt`

    /**
     * @notice Allows strategists to repay loan debt on Fraxlend Pair.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param tokenToRepay the underlying ERC20 token you want to repay, NOT the debtToken. TODO: not sure if we want this to be pulling from the fraxlendPair the assetToken, or to just have this be FRAX since it always is FRAX and doesn't sound like it will change. NOTE that the assetContract is actually internal var within fraxlend pair.
     * @param amountToRepay the amount of `tokenToRepay` to repay with.
     * NOTE: TODO: CRISPY QUESTION - this is the simpler version but I think we ought to go with something closer to the alternative (see comments in next function).
     */
    function repayFraxlendDebt(
        IFToken fToken,
        ERC20 tokenToRepay,
        uint256 sharesToRepay
    ) public {
        uint256 fraxlendRepayAmount = _toBorrowAmount(fToken, sharesToRepay, false, ACCOUNT_FOR_INTEREST);
        tokenToRepay.safeApprove(address(fToken), fraxlendRepayAmount);
        fToken.repayAsset(sharesToRepay, msg.sender);
        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToRepay, address(fToken));
    }

    /**
     * @notice Allows strategists to repay loan debt on Fraxlend Pair.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param tokenToRepay the underlying ERC20 token you want to repay, NOT the debtToken. TODO: not sure if we want this to be pulling from the fraxlendPair the assetToken, or to just have this be FRAX since it always is FRAX and doesn't sound like it will change.
     * @param amountToRepay the amount of `tokenToRepay` to repay with.
     * NOTE: this version of repayFraxlendDebt is meant to offer an alternative to doing it similar to the AaveDebtTokenAdaptor (see notes below)
     * TODO: CRISPY --> from `FraxlendCore.sol` functions `repayAsset()` and `_repayAsset()` I don't see specific responses from the contracts if the amount of shares repaid >> amount of borrowShares even owed. Unless `-=` takes care of that.
     * Assuming the above is true, then we'll need to check how much borrowShares we need to pay. Then we can get the total amount of Frax we need to repay. So we could specify the amount of FRAX we're willing to repay (could be max), and then we calculate the amount of FRAX owing from fraxlend, then we check the two values to make sure it is less than the amount we're willing to repay. From there we can simply repay the shares. We then check that we have the expected change in borrowShares as per FraxLend accounting.
     */
    function repayFraxlendDebt2(
        IFToken fToken,
        ERC20 tokenToRepay,
        uint256 maxAmountToRepay,
        uint256 sharesToRepay
    ) public {
        // Check that max amount to repay from FraxlendPair is less than specified maxAmountToRepay
        uint256 fraxlendRepayAmount = _toBorrowAmount(fToken, sharesToRepay, false, ACCOUNT_FOR_INTEREST);
        if (fraxlendRepayAmount > maxAmountToRepay)
            revert DebtFTokenAdaptor__AmountOwingExceedsSpecifiedRepaymentMax(address(fToken));

        tokenToRepay.safeApprove(address(fToken), fraxlendRepayAmount);

        uint256 expectedBorrowShares = fToken.userBorrowShares[msg.sender] - sharesToRepay; // TODO: see note in comment above
        fToken.repayAsset(sharesToRepay, msg.sender);
        // double check that the borrowShares have reduced by proper amount for cellar
        if (fToken.userBorrowShares[msg.sender] != expectedBorrowShares)
            revert DebtFTokenAdaptor__RepaymentShareAmountDecrementedIncorrectly(address(fToken)); // TODO: see note in comment above
        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToRepay, address(fToken));
    }

    /**
     * @notice Allows a strategist to call `addInterest` on a Frax Pair they are using.
     * @dev A strategist might want to do this if a Frax Lend pair has not been interacted
     *      in a while, and the strategist does not plan on interacting with it during a
     *      rebalance.
     * @dev Calling this can increase the share price during the rebalance,
     *      so a strategist should consider moving some assets into reserves.
     * TODO: CRISPY Question - do we need this here?
     */
    function callAddInterest(IFToken fToken) public {
        _validateFToken(fToken);
        _addInterest(fToken);
    }

    /**
     * @notice Validates that a given fToken is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateFToken(IFToken fToken) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(address(fToken))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert FTokenAdaptor__FTokenPositionsMustBeTracked(address(fToken));
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // The Frax Pair interface can slightly change between versions.
    // To account for this, FTokenAdaptors (including debt and collateral adaptors) will use the below internal functions when
    // interacting with Frax Pairs, this way new pairs can be added by creating a
    // new contract that inherits from this one, and overrides any function it needs
    // so it conforms with the new Frax Pair interface.

    // Current versions in use for `FraxLendPair` include v1 and v2.

    // IMPORTANT: This `DebtFTokenAdaptor.sol` is associated to the v2 version of `FraxLendPair`
    // whereas DebtFTokenAdaptorV1 is actually associated to `FraxLendPairv1`.
    // The reasoning to name it like this was to set up the base DebtFTokenAdaptor for the
    // most current version, v2. This is in anticipation that more FraxLendPairs will
    // be deployed following v2 in the near future. When later versions are deployed,
    // then the described inheritance pattern above will be used.
    //===============================================================================

    /**
     * @notice Converts a given number of borrow shares to debtToken amount from specified 'v2' FraxLendPair
     * @dev This is one of the adjusted functions from v1 to v2. ftoken.toBorrowAmount() calls into the respective version (v2 by default) of FraxLendPair
     * @param fToken The specified FraxLendPair
     * @param shares Shares of debtToken
     * @param roundUp Whether to round up after division
     * @param previewInterest Whether to preview interest accrual before calculation
     */
    function _toBorrowAmount(
        IFToken fToken,
        uint256 _shares,
        bool _roundUp,
        bool _previewInterest
    ) internal view virtual returns (uint256) {
        return fToken.toBorrowAmount(_shares, _roundUp, _previewInterest);
    }

    /**
     * @notice Caller calls `addInterest` on specified 'v2' FraxLendPair
     * @dev ftoken.addInterest() calls into the respective version (v2 by default) of FraxLendPair
     * @param fToken The specified FraxLendPair
     * TODO: not sure if we need this
     */
    function _addInterest(IFToken fToken) internal virtual {
        fToken.addInterest(false);
    }

    /// @notice The ```_isSolvent``` function determines if a given borrower is solvent given an exchange rate
    /// @param _borrower The borrower address to check
    /// @param _exchangeRate The exchange rate, i.e. the amount of collateral to buy 1e18 asset
    /// @return Whether borrower is solvent
    /// @dev NOTE: TODO: EIN - mainly copied from `FraxlendPairCore.sol` so this needs reworking in full.
    /// NOTE:  This is not working yet, convert this in a gas efficient manner to work with this adaptor. Not sure about it though...
    function _isSolvent(address _borrower, uint256 _exchangeRate) internal view returns (bool) {
        if (maxLTV == 0) return true;
        uint256 _borrowerAmount = totalBorrow.toAmount(userBorrowShares[_borrower], true);
        if (_borrowerAmount == 0) return true;
        uint256 _collateralAmount = userCollateralBalance[_borrower];
        if (_collateralAmount == 0) return false;

        uint256 _ltv = (((_borrowerAmount * _exchangeRate) / EXCHANGE_PRECISION) * LTV_PRECISION) / _collateralAmount;
        return _ltv <= maxLTV;
    }
}
