// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { MorphoBlueHealthFactorLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHealthFactorLogic.sol";
import { IMorpho, MarketParams, Id } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { SharesMathLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/SharesMathLib.sol";

/**
 * @title Morpho Blue Debt Token Adaptor
 * @notice Allows Cellars to borrow assets from Morpho Blue pairs.
 * @dev  *      To interact with a different version or custom market, a new
 *      adaptor will inherit from this adaptor
 *      and override the interface helper functions. MB refers to Morpho
 *      Blue
 * @author crispymangoes, 0xEinCodes
 */
contract MorphoBlueDebtAdaptor is BaseAdaptor, MorphoBlueHealthFactorLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using SharesMathLib for uint256;

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

    constructor(
        bool _accountForInterest,
        address _morphoBlue,
        uint256 _healthFactor
    ) MorphoBlueHealthFactorLogic(_morphoBlue) {
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
     * @return Identifier unique to this adaptor for a shared registry.
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
     * @notice Returns the cellar's balance of the respective MB market loanToken calculated from cellar borrow shares according to MB prod contracts
     * @param adaptorData encoded bytes32 MB id that represents the MB market for this position
     * TODO: EIN should this account for interest? If yes, We could use the library to simulate the expected debt with interest, or we could kick morphoblue contract to get accrued interest. I lean towards the former, but since balanceOf() is not a mutative function. It depends how frequent the contract is kicked I guess (morpho blue that is).
     * @return Cellar's balance of the respective MB market loanToken
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        Id id = abi.decode(adaptorData, (Id));
        _validateMBMarket(id);
        return _userBorrowBalance(id);
    }

    /**
     * @notice Returns `loanToken` from respective MB market
     * @param adaptorData encoded bytes32 MB id that represents the MB market for this position
     * @return `loanToken` from respective MB market
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        Id id = abi.decode(adaptorData, (Id));
        _validateMBMarket(id);
        MarketParams memory market = morphoBlue.idToMarketParams(id);
        return ERC20(market.loanToken);
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     * @return Whether or not this adaptor is in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================

    // `borrowAsset`
    /**
     * @notice Allows strategists to borrow assets from Morpho Blue.
     * @param _id encoded bytes32 MB id that represents the MB market for this position.
     * @param _amountToBorrow the amount of `loanToken` to borrow on the specified MB market.
     */
    function borrowFromMorphoBlue(Id _id, uint256 _amountToBorrow) public {
        _validateMBMarket(_id);
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        _borrowAsset(market, _amountToBorrow, address(this));

        // Check if borrower is insolvent (AKA they have bad LTV), revert if they are
        if (minimumHealthFactor > (_getHealthFactor(_id, market))) {
            revert MorphoBlueDebtAdaptor__HealthFactorTooLow(_id);
        }
    }

    // `repayDebt`

    /**
     * @notice Allows strategists to repay loan debt on Morph Blue Lending Market. Make sure to call addInterest() beforehand to ensure we are repaying what is required.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param _id Encoded bytes32 MB id that represents the MB market for this position.
     * @param _debtTokenRepayAmount The amount of `loanToken` to repay.
     */
    function repayMorphoBlueDebt(Id _id, uint256 _debtTokenRepayAmount) public {
        _validateMBMarket(_id);

        // TODO: as per chat w/ Crispy accrueInterest() and then add a conditional logic check that it takes the total debt if the passed in repayAmount is greater than the debt that is actually within the position.
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        ERC20 tokenToRepay = ERC20(market.loanToken);

        uint256 debtAmountToRepay = _maxAvailable(tokenToRepay, _debtTokenRepayAmount);

        // using Morpho sharesLibrary we can calculate the sharesToRepay from the debtAmount
        uint256 totalBorrowAssets = morphoBlue.market(_id).totalBorrowAssets;
        uint256 totalBorrowShares = morphoBlue.market(_id).totalBorrowShares;

        uint256 sharesToRepay = debtAmountToRepay.toSharesUp(totalBorrowAssets, totalBorrowShares); // get the total assets and total borrow shares of the market

        // TODO - check that Morpho Blue reverts if the repayment amount exceeds the amount of debt the user even has. If it does, that's how we handle doing type(uint256).max when we don't owe that much.
        // TODO - check if Morpho Blue reverts if there is no debt. If it doesn't have its own revert, then use MorphoBlueDebtAdaptor__CannotRepayNoDebt();

        tokenToRepay.safeApprove(address(morphoBlue), type(uint256).max);
        _repayAsset(market, sharesToRepay, address(this));
        _revokeExternalApproval(tokenToRepay, address(morphoBlue));
    }

    /**
     * @notice Allows a strategist to call `accrueInterest()` on a MB Market cellar is using.
     * @dev A strategist might want to do this if a MB market has not been interacted with
     *      in a while, and the strategist does not plan on interacting with it during a
     *      rebalance.
     * @dev Calling this can increase the share price during the rebalance,
     *      so a strategist should consider moving some assets into reserves.
     * @param _id encoded bytes32 MB id that represents the MB market for this position.
     */
    function accrueInterest(Id _id) public {
        _validateMBMarket(_id);
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        _accrueInterest(market);
    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Validates that a given Id is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     * @param _id encoded bytes32 MB id that represents the MB market for this position.
     */
    function _validateMBMarket(Id _id) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_id)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert MorphoBlueDebtAdaptor__MarketPositionsMustBeTracked(_id);
    }

    //============================== Interface Details ==============================
    // General message on interface and virtual functions below: The Morpho Blue protocol is meant to be a primitive layer to DeFi, and so other projects may build atop of MB. These possible future projects may implement the same interface to simply interact with MB, and thus this adaptor is implementing a design that allows for future adaptors to simply inherit this "Base Morpho Adaptor" and override what they need appropriately to work with whatever project. Aspects that may be adjusted include using the flexible `bytes` param within `morphoBlue.supplyCollateral()` for example.

    // Current versions in use are just for the primitive Morpho Blue deployments.
    // IMPORTANT: Going forward, other versions will be renamed w/ descriptive titles for new projects extending off of these primitive contracts.
    //===============================================================================

    /**
     * @notice Helper function to borrow specific amount of `loanToken` in cellar account within specific MB market.
     * @param _market The specified MB market
     * @param _borrowAmount The amount of borrowAsset to borrow
     * @param _onBehalf The receiver of the amount of `loanToken` borrowed and receiver of debt accounting-wise.
     */
    function _borrowAsset(MarketParams memory _market, uint256 _borrowAmount, address _onBehalf) internal virtual {
        morphoBlue.borrow(_market, _borrowAmount, 0, _onBehalf, _onBehalf);
    }

    /**
     * @notice Helper function to repay specific MB market debt by an amount
     * @param _market The specified MB market
     * @param _sharesToRepay The amount of borrowShares to repay
     * @param _onBehalf The address of the debt-account reduced due to this repayment within MB market.
     */
    function _repayAsset(MarketParams memory _market, uint256 _sharesToRepay, address _onBehalf) internal virtual {
        morphoBlue.repay(_market, 0, _sharesToRepay, _onBehalf, hex""); // See IMorpho.sol for more detail, but the 2nd param is 0 because we specify borrowShares, not borrowAsset amount. Users need to choose btw repaying specifying amount of borrowAsset, or borrowShares.
    }
}
