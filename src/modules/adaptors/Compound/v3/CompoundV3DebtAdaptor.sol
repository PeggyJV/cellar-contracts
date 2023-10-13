// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";
import { FraxlendHealthFactorLogic } from "src/modules/adaptors/Frax/FraxlendHealthFactorLogic.sol";
import { CometInterface } from "src/interfaces/external/Compound/CometInterface.sol";
import { CompoundV3ExtraLogic } from "src/modules/adaptors/Compound/v3/CompoundV3ExtraLogic.sol";

/**
 * @title CompoundV3 Debt Token Adaptor
 * @notice Allows Cellars to borrow assets from CompoundV3 Lending Markets.
 * @author crispymangoes, 0xEinCodes
 * NOTE: In efforts to keep the smart contracts simple, the three main services for accounts with CompoundV3; supplying `BaseAssets`, supplying `Collateral`, and `Borrowing` against `Collateral` are isolated to three separate adaptor contracts. Therefore, repayment of open `borrow` positions are done within this adaptor, and cannot be carried out through the use of `CompoundV3SupplyAdaptor`.
 */
contract CompoundV3DebtAdaptor is BaseAdaptor, CompoundV3ExtraLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //============================================ Notice ===========================================
    // TODO: populate if needed for things like "kick" required, etc.

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address CompoundMarket, address asset)
    // Where:
    // `CompoundMarket` is the CompoundV3 Lending Market address and `asset` is the address of the ERC20 that this adaptor is working with
    //================= Configuration Data Specification =================
    // NA
    //
    //====================================================================

    /**
     * @notice Attempted tx that results in unhealthy cellar
     */
    error CompoundV3DebtAdaptor_HealthFactorTooLow(address compMarket);

    /**
     * @notice Attempted repayment when no debt position in compMarket for cellar
     * TODO: see if compound even allows this, like how Fraxlend seemed to allow it. I guess it shouldn't because it shouldn't allow a `supply` to be open when a `borrow` is open, and that logic should extend to if a `collateral` position is open.
     */
    error CompoundV3DebtAdaptor_CannotRepayNoDebt(address compMarket);

    /**
     * @notice This bool determines how this adaptor accounts for interest.
     *         True: Account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     *         False: Do not account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     * TODO: if account's debt balance is updated constantly then it always accounts for interest. If not, then we need to plan accordingly.
     */
    bool public immutable ACCOUNT_FOR_INTEREST;

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(bool _accountForInterest, uint256 _healthFactor) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        ACCOUNT_FOR_INTEREST = _accountForInterest;
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
        return keccak256(abi.encode("CompoundV3 DebtToken Adaptor V 1.0"));
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
     * @notice Returns the cellar's balance of the respective CompoundV3 Lending Market debtToken (`baseAsset`)
     * @param adaptorData the CompMarket and Asset combo the Cellar position corresponds to
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (CometInterface compMarket, ERC20 asset) = abi.decode(adaptorData, (CometInterface, ERC20));

        _validateCompMarketAndAsset(compMarket, asset);
        return compMarket.borrowBalanceOf(address(this)); // RETURNS: The balance of the base asset, including interest, borrowed by the specified account as an unsigned integer scaled up by 10 to the “decimals” integer in the asset’s contract. TODO: assess how we need to work with this return value, decimals-wise.
    }

    /**
     * @notice Returns `assetContract` from respective fraxlend pair, but this is most likely going to be FRAX.
     * TODO: calculating the CR or health factor will determine if we need to have the collateralAsset as an adaptorData param. The question revolves around how the protocol keeps track of the different ceilings of each asset for the protocol vs the account balance of said collateral, and then the resultant `baseAsset` balance.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        (CometInterface compMarket, ) = abi.decode(adaptorData, CometInterface, ERC20);
        return ERC20(compMarket.baseToken());
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
     * @notice Allows strategists to borrow assets from CompoundV3 Lending Market.
     * @param _compMarket The specified CompoundV3 Lending Market
     * @param amountToBorrow the amount of `baseAsset` to borrow on respective compMarket
     * NOTE: need to take the higher value btw minBorrowAmount and amountToBorrow or else will revert
     */
    function borrowFromCompoundV3(CometInterface _compMarket, uint256 amountToBorrow) public {
        _validateCompMarketAndAsset(compMarket, asset); // TODO: fix - see other TODOs here re: health factor calcs.
        ERC20 baseToken = ERC20(compMarket.baseToken());

        // TODO: do we want to have conditional logic handle when the strategist passes in `type(uint256).max`?

        // query compMarket to assess minBorrowAmount
        uint256 minBorrowAmount = uint256((_compMarket.getConfiguration(_compMarket)).baseBorrowMin); // see `CometConfiguration.sol` for `struct Configuration`

        amountToBorrow = minBorrowAmount > amountToBorrow ? minBorrowAmount : amountToBorrow;

        // TODO: do we want to compare requested `amountToBorrow` against what is allowed to be borrowed?

        compMarket.withdraw(address(baseToken), amountToBorrow);

        // TODO: Health Factor logic implementation.
    }

    // `repayDebt`

    /**
     * @notice Allows strategists to repay loan debt on CompoundV3 Lending Market.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param _compMarket the Fraxlend Pair to repay debt from.
     * @param _debtTokenRepayAmount the amount of `debtToken` (`baseAsset`) to repay with.
     */
    function repayFraxlendDebt(CometInterface _compMarket, uint256 _debtTokenRepayAmount) public {
        _validateCompMarketAndAsset(_compMarket, asset); // TODO: fix - see other TODOs here re: health factor calcs.
        ERC20 baseToken = ERC20(compMarket.baseToken());

        _debtTokenRepayAmount = _maxAvailable(baseToken, _debtTokenRepayAmount); // TODO: check what happens when one tries to repay more than what they owe in CompoundV3, and what happens if they try to repay on an account that shows zero for their collateral, or for their loan?

        uint256 debtToRepayAccCompoundV3 = _compMarket.borrowBalanceOf(address(this));

        _debtTokenRepayAmount = debtToRepayAccCompoundV3 < _debtTokenRepayAmount
            ? debtToRepayAccCompoundV3
            : _debtTokenRepayAmount;

        baseToken.safeApprove(address(_compMarket), type(uint256).max);

        // finally repay debt
        _compMarket.supply(address(baseToken), _debtTokenRepayAmount);

        _revokeExternalApproval(tokenToRepay, address(_compMarket));
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
     * @notice Converts a given asset amount to a number of asset shares (fTokens) from specified 'v2' Fraxlend Pair
     * @dev This is one of the adjusted functions from v1 to v2. ftoken.toAssetShares() calls into the respective version (v2 by default) of Fraxlend Pair
     * @param fToken The specified Fraxlend Pair
     * @param amount The amount of asset
     * @param roundUp Whether to round up after division
     * @param previewInterest Whether to preview interest accrual before calculation
     * @return number of asset shares
     */
    function _toAssetShares(
        IFToken fToken,
        uint256 amount,
        bool roundUp,
        bool previewInterest
    ) internal view virtual returns (uint256) {
        return fToken.toAssetShares(amount, roundUp, previewInterest);
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
