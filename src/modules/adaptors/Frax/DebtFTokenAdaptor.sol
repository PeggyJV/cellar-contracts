// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";
import { FraxlendHealthFactorLogic } from "src/modules/adaptors/Frax/FraxlendHealthFactorLogic.sol";

/**
 * @title FraxLend Debt Token Adaptor
 * @notice Allows Cellars to borrow assets from FraxLend pairs.
 * @author crispymangoes, 0xEinCodes
 * NOTE: repayAssetWithCollateral() is not allowed from strategist to call in FraxlendCore for cellar.
 */
contract DebtFTokenAdaptor is BaseAdaptor, FraxlendHealthFactorLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //============================================ Notice ===========================================
    // Since there is no way to calculate pending interest for this positions balanceOf,
    // The positions balance is only updated when accounts interact with the
    // Frax Lend pair this position is working with.
    // This can lead to a divergence from the Cellars share price, and its real value.
    // This can be mitigated by calling `callAddInterest` on Frax Lend pairs
    // that are not frequently interacted with.

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
     * @notice Attempted tx that results in unhealthy cellar
     */
    error DebtFTokenAdaptor__HealthFactorTooLow(address fraxlendPair);

    /**
     * @notice Attempted repayment when no debt position in fraxlendPair for cellar
     */
    error DebtFTokenAdaptor__CannotRepayNoDebt(address fraxlendPair);

    /**
     * @notice The FRAX contract on current network.
     * @notice For mainnet use 0x853d955aCEf822Db058eb8505911ED77F175b99e.
     */
    ERC20 public immutable FRAX;

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

    constructor(bool _accountForInterest, address _frax, uint256 _healthFactor) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        ACCOUNT_FOR_INTEREST = _accountForInterest;
        FRAX = ERC20(_frax);
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
        return keccak256(abi.encode("FraxLend debtTokenV2 Adaptor V 1.1"));
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
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        IFToken fraxlendPair = abi.decode(adaptorData, (IFToken));
        uint256 borrowShares = _userBorrowShares(fraxlendPair, msg.sender);
        return _toBorrowAmount(fraxlendPair, borrowShares, false, ACCOUNT_FOR_INTEREST);
    }

    /**
     * @notice Returns `assetContract` from respective fraxlend pair, but this is most likely going to be FRAX.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IFToken fraxlendPair = abi.decode(adaptorData, (IFToken));
        return ERC20(_fraxlendPairAsset(fraxlendPair));
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
     */
    function borrowFromFraxlend(IFToken fraxlendPair, uint256 amountToBorrow) public {
        _validateFToken(fraxlendPair);
        _borrowAsset(amountToBorrow, fraxlendPair);

        // Check health factor is still satisfactory
        uint256 _exchangeRate = _getExchangeRateInfo(fraxlendPair);
        // Check if borrower is insolvent after this borrow tx, revert if they are
        if (minimumHealthFactor > (_getHealthFactor(fraxlendPair, _exchangeRate))) {
            revert DebtFTokenAdaptor__HealthFactorTooLow(address(fraxlendPair));
        }
    }

    // `repayDebt`

    /**
     * @notice Allows strategists to repay loan debt on Fraxlend Pair. Make sure to call addInterest() beforehand to ensure we are repaying what is required.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param _fraxlendPair the Fraxlend Pair to repay debt from.
     * @param _debtTokenRepayAmount the amount of `debtToken` to repay with.
     */
    function repayFraxlendDebt(IFToken _fraxlendPair, uint256 _debtTokenRepayAmount) public {
        _validateFToken(_fraxlendPair);
        ERC20 tokenToRepay = ERC20(_fraxlendPairAsset(_fraxlendPair));
        uint256 debtTokenToRepay = _maxAvailable(tokenToRepay, _debtTokenRepayAmount);
        uint256 sharesToRepay = _toBorrowShares(_fraxlendPair, debtTokenToRepay, false, true);
        uint256 sharesAccToFraxlend = _userBorrowShares(_fraxlendPair, address(this)); // get fraxlendPair's record of borrowShares atm
        if (sharesAccToFraxlend == 0) revert DebtFTokenAdaptor__CannotRepayNoDebt(address(_fraxlendPair)); // NOTE: from checking it out, unless `userBorrowShares[_borrower] -= _shares;` reverts, then fraxlendCore lets users repay FRAX w/ no limiters.

        // take the smaller btw sharesToRepay and sharesAccToFraxlend
        if (sharesAccToFraxlend < sharesToRepay) {
            sharesToRepay = sharesAccToFraxlend;
        }
        tokenToRepay.safeApprove(address(_fraxlendPair), type(uint256).max);

        _repayAsset(_fraxlendPair, sharesToRepay);

        _revokeExternalApproval(tokenToRepay, address(_fraxlendPair));
    }

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
     * @notice Validates that a given fraxlendPair is set up as a position in the Cellar.
     * @param _fraxlendPair The specified Fraxlend Pair
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateFToken(IFToken _fraxlendPair) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(address(_fraxlendPair))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked(address(_fraxlendPair));
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

    /**
     * @notice gets the asset of the specified fraxlend pair
     * @param _fraxlendPair The specified Fraxlend Pair
     * @return asset of fraxlend pair
     */
    function _fraxlendPairAsset(IFToken _fraxlendPair) internal view virtual returns (address asset) {
        return _fraxlendPair.asset();
    }

    /**
     * @notice Caller calls `addInterest` on specified 'v2' Fraxlend Pair
     * @dev fraxlendPair.addInterest() calls into the respective version (v2 by default) of Fraxlend Pair
     * @param fraxlendPair The specified Fraxlend Pair
     */
    function _addInterest(IFToken fraxlendPair) internal virtual {
        fraxlendPair.addInterest(false);
    }

    /**
     * @notice Converts a given asset amount to a number of borrow shares from specified 'v2' Fraxlend Pair
     * @dev This is one of the adjusted functions from v1 to v2. ftoken.toBorrowAmount() calls into the respective version (v2 by default) of Fraxlend Pair
     * @param fToken The specified Fraxlend Pair
     * @param amount The amount of asset
     * @param roundUp Whether to round up after division
     * @param previewInterest Whether to preview interest accrual before calculation
     * @return number of borrow shares
     */
    function _toBorrowShares(
        IFToken fToken,
        uint256 amount,
        bool roundUp,
        bool previewInterest
    ) internal view virtual returns (uint256) {
        return fToken.toBorrowShares(amount, roundUp, previewInterest);
    }

    /**
     * @notice Borrow amount of borrowAsset in cellar account within fraxlend pair
     * @param _borrowAmount The amount of borrowAsset to borrow
     * @param _fraxlendPair The specified Fraxlend Pair
     */
    function _borrowAsset(uint256 _borrowAmount, IFToken _fraxlendPair) internal virtual {
        _fraxlendPair.borrowAsset(_borrowAmount, 0, address(this)); // NOTE: explitly have the collateral var as zero so Strategists must do collateral increasing tx via the CollateralFTokenAdaptor for this fraxlendPair
    }

    /**
     * @notice Caller calls `updateExchangeRate()` on specified FraxlendV2 Pair
     * @param _fraxlendPair The specified FraxLendPair
     * @return exchangeRate needed to calculate the current health factor
     */
    function _getExchangeRateInfo(IFToken _fraxlendPair) internal virtual returns (uint256 exchangeRate) {
        exchangeRate = _fraxlendPair.exchangeRateInfo().highExchangeRate;
    }

    /**
     * @notice Repay fraxlend pair debt by an amount
     * @param _fraxlendPair The specified Fraxlend Pair
     * @param sharesToRepay The amount of shares to repay
     */
    function _repayAsset(IFToken _fraxlendPair, uint256 sharesToRepay) internal virtual {
        _fraxlendPair.repayAsset(sharesToRepay, address(this));
    }
}
