// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";

/**
 * @title FraxLend Debt Token Adaptor
 * @notice Allows Cellars to borrow assets from FraxLend pairs.
 * @author crispymangoes, 0xEinCodes
 * TODO: remove this when done -> NOTE: toAssetAmount() has 3 vars in newest version, in older version it only has two.
 * TODO: Carry out setup and tests for v1Adaptors too
 */
contract DebtFTokenAdaptorV2 is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    //
    // adaptorData = abi.encode(address fraxlendPair)
    // Where:
    // `fraxlendPair` is the fraxlend pair this adaptor position is working with. It is also synomous to fToken used in `FTokenAdaptor.sol` and `FTokenAdaptorV1.sol`
    //================= Configuration Data Specification =================
    //
    //====================================================================

    /**
     * @notice Attempted to interact with an fraxlendPair the Cellar is not using.
     */
    error DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked(address fraxlendPair);

    /**
     * @notice Attempted tx that results in unhealthy cellar LTV
     */
    error DebtFTokenAdaptor__LTVTooLow(address fraxlendPair);

    /**
     * @notice Fraxlend Pair contract reporting higher repayment amount than Strategist is comfortable with according to Strategist params.
     * @dev TODO: see notes for function involved. This may not be needed.
     */
    error DebtFTokenAdaptor__AmountOwingExceedsSpecifiedRepaymentMax(address fraxlendPair);

    /**
     * @notice Unexpected result in borrow shares within fraxlend pair after repayment
     * TODO: not sure if we want it like this, this basically blocks repayments if the accounting is different btw this adaptor and the fraxlend pair.
     */
    error DebtFTokenAdaptor__RepaymentShareAmountDecrementedIncorrectly(address fraxlendPair);

    /**
     * @notice The FRAX contract on current network.
     * @notice For mainnet use 0x853d955aCEf822Db058eb8505911ED77F175b99e.
     */
    ERC20 public immutable FRAX;

    /**
     * @notice maxLTV that is actually lower than the LTV allowed by Fraxlend. This prevents cellar lending positions from being too at risk.
     */
    uint256 public immutable maxLTV;

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

    constructor(
        bool _accountForInterest,
        address _frax,
        uint256 _maxLTV
    ) {
        // _verifyConstructorMinimumHealthFactor(1.mulDivDown(1, _maxLTV)); // TODO: EIN - figure out best way to convert this.
        ACCOUNT_FOR_INTEREST = _accountForInterest; //TODO: I think we need this, but need to double check for lending/borrowing setup in Fraxlend.
        FRAX = ERC20(_frax);
        maxLTV = _maxLTV;
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
     * @param adaptorData encoded fraxlendPair (fToken) for this position
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        IFToken fraxlendPair = abi.decode(adaptorData, (IFToken));
        return _toBorrowAmount(fraxlendPair, fraxlendPair.userBorrowShares(msg.sender), false, ACCOUNT_FOR_INTEREST);
    }

    /**
     * @notice Returns `assetContract` from respective fraxlendPair, but this is most likely going to be FRAX.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IFToken fraxlendPair = abi.decode(adaptorData, (IFToken));
        return ERC20(fraxlendPair.asset());
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
     * @param fraxlendPair the Fraxlend Pair to borrow from.
     * @param amountToBorrow the amount of `debtTokenToBorrow` to borrow on Fraxlend.
     * NOTE: `borrowAsset` is the same btw v1 and v2 FraxlendPairs
     * TODO: See helper `_isSolvent` --> NOTE that it is the same helper in CollateralFTokenAdaptor, so once either is figured out just copy and paste the proper solution.
     */
    function borrowFromFraxlend(IFToken fraxlendPair, uint256 amountToBorrow) public {
        // Check that debt position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(address(fraxlendPair))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked(address(fraxlendPair));

        fraxlendPair.borrowAsset(amountToBorrow, 0, address(this)); // NOTE: explitly have the collateral var as zero so Strategists must do collateral increasing tx via the CollateralFTokenAdaptor for this fraxlendPair

        // Check LTV is still satisfactory
        (, uint256 _exchangeRate, ) = fraxlendPair.updateExchangeRate(); // needed to calculate LTV in next line
        // Check if borrower is insolvent after this borrow tx, revert if they are
        if (!_isSolvent(fraxlendPair, _exchangeRate)) {
            revert DebtFTokenAdaptor__LTVTooLow(address(fraxlendPair));
        }
    }

    // `repayDebt`

    /**
     * @notice Allows strategists to repay loan debt on Fraxlend Pair.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param _fraxlendPair the Fraxlend Pair to repay debt from.
     * @param _tokenToRepay the underlying ERC20 token you want to repay, NOT the debtToken. TODO: not sure if we want this to be pulling from the fraxlendPair the assetToken, or to just have this be FRAX since it always is FRAX and doesn't sound like it will change.
     * @param _maxAmountToRepay the amount of `tokenToRepay` to repay with.
     * @param _sharesToRepay the amount of borrowShares to repay within Fraxlend pair.
     * TODO: CRISPY --> from `FraxlendCore.sol` functions `repayAsset()` and `_repayAsset()` I don't see specific responses from the contracts if the amount of shares repaid >> amount of borrowShares even owed. Unless `-=` takes care of that.
     * Assuming the above is true, then we'll need to check how much borrowShares we need to pay. Then we can get the total amount of Frax we need to repay. So we could specify the amount of FRAX we're willing to repay (could be max), and then we calculate the amount of FRAX owing from fraxlend, then we check the two values to make sure it is less than the amount we're willing to repay. From there we can simply repay the shares. We then check that we have the expected change in borrowShares as per FraxLend accounting.
     * TODO: possibly add a bool and logic that will take the amount of FRAX required to repay the debt. I guess this could be unecessary since if we just do maxAvailable we'll pay with all the FRAX possible.
     */
    function repayFraxlendDebt(
        IFToken _fraxlendPair,
        ERC20 _tokenToRepay,
        uint256 _maxAmountToRepay,
        uint256 _sharesToRepay
    ) public {
        // TODO: add a maxAvailable check to see how much is needed to repay off entire loan
        // amountToRepay = _maxAvailable(FRAX, maxAmountToRepay);
        uint256 sharesToRepay = _fraxlendPair.userBorrowShares(address(this)); 
        if(_sharesToRepay < sharesToRepay) sharesToRepay = _sharesToRepay;
        // Check that max amount to repay from FraxlendPair is less than specified maxAmountToRepay
        uint256 fraxlendRepayAmount = _toBorrowAmount(_fraxlendPair, sharesToRepay, false, ACCOUNT_FOR_INTEREST);
        // TODO: console.log fraxlendRepayAmount
        if (fraxlendRepayAmount > _maxAmountToRepay)
            revert DebtFTokenAdaptor__AmountOwingExceedsSpecifiedRepaymentMax(address(_fraxlendPair));

        // _tokenToRepay.safeApprove(address(_fraxlendPair), fraxlendRepayAmount);
        _tokenToRepay.safeApprove(address(_fraxlendPair), type(uint256).max);

        uint256 expectedBorrowShares = _fraxlendPair.userBorrowShares(address(this)) - sharesToRepay; // TODO: see note in comment above
        _fraxlendPair.repayAsset(sharesToRepay, address(this));
        // double check that the borrowShares have reduced by proper amount for cellar
        if (_fraxlendPair.userBorrowShares(address(this)) != expectedBorrowShares)
            revert DebtFTokenAdaptor__RepaymentShareAmountDecrementedIncorrectly(address(_fraxlendPair)); // TODO: see note in comment above
        // Zero out approvals if necessary.
        _revokeExternalApproval(_tokenToRepay, address(_fraxlendPair));
    }

    /**
     * @notice Allows a strategist to call `addInterest` on a Frax Pair they are using.
     * @dev A strategist might want to do this if a Frax Lend pair has not been interacted
     *      in a while, and the strategist does not plan on interacting with it during a
     *      rebalance.
     * @dev Calling this can increase the share price during the rebalance,
     *      so a strategist should consider moving some assets into reserves.
     */
    function callAddInterest(IFToken fraxlendPair) public {
        _validateFToken(fraxlendPair);
        _addInterest(fraxlendPair);
    }

    /**
     * @notice Validates that a given fraxlendPair is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateFToken(IFToken fraxlendPair) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(address(fraxlendPair))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked(address(fraxlendPair));
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

    /**
     * @notice Caller calls `addInterest` on specified 'v2' FraxLendPair
     * @dev fraxlendPair.addInterest() calls into the respective version (v2 by default) of FraxLendPair
     * @param fraxlendPair The specified FraxLendPair
     * TODO: not sure if we need this
     */
    function _addInterest(IFToken fraxlendPair) internal virtual {
        fraxlendPair.addInterest(false);
    }

    /// @notice The ```_isSolvent``` function determines if a given borrower is solvent given an exchange rate
    /// @param _exchangeRate The exchange rate, i.e. the amount of collateral to buy 1e18 asset
    /// @return Whether borrower is solvent
    /// NOTE: in theory, this should work. It calls `_toBorrowAmount()` which ends up calling `toBorrowAmount()` directly from the `FraxlendPair.sol` contract per pair. It generates the borrowAmount based on interest-adjusted totalBorrow and shares within that pair. `_collateralAmount` is also pulled directly via getters in the pair contracts themselves.
    /// @dev NOTE: TODO: EIN - TEST - this needs to be tested in comparison the `_isSolvent` calcs in Fraxlend so we are calculating the same thing at all times.
    /// NOTE:  TODO: This is not working yet, convert this in a gas efficient manner to work with this adaptor. Not sure about it though...
    function _isSolvent(IFToken _fraxlendPair, uint256 _exchangeRate) internal view returns (bool) {
        if (maxLTV == 0) return true;
        // calculate the borrowShares
        uint256 borrowerShares = _fraxlendPair.userBorrowShares(address(this));
        uint256 _borrowerAmount = _toBorrowAmount(_fraxlendPair, borrowerShares, true, true); // need interest-adjusted and conservative amount (round-up) similar to `_isSolvent()` function in actual Fraxlend contracts.
        if (_borrowerAmount == 0) return true;
        uint256 _collateralAmount = _fraxlendPair.userCollateralBalance(address(this));
        if (_collateralAmount == 0) return false;

        (uint256 LTV_PRECISION, , , , uint256 EXCHANGE_PRECISION, , , ) = _fraxlendPair.getConstants();

        uint256 _ltv = (((_borrowerAmount * _exchangeRate) / EXCHANGE_PRECISION) * LTV_PRECISION) / _collateralAmount;
        return _ltv <= maxLTV;
    }
}
