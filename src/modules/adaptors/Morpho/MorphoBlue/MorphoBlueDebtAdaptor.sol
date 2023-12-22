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

    constructor(bool _accountForInterest, address _morphoBlue, uint256 _healthFactor) MorphoBlueHealthFactorLogic(_morphoBlue) {
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
     * TODO: EIN does this account for interest? We could use the library to simulate the expected debt with interest, or we could kick morphoblue contract to get accrued interest. I lean towards the former, but since balanceOf() is not a mutative function. It depends how frequent the contract is kicked I guess (morpho blue that is).
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        return _userBorrowBalance(_id, market);
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
    function borrowFromMorphoBlue(Id _id, uint256 _amountToBorrow, uint256 _shares) public {
        _validateMBMarket(_id);
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        _borrowAsset(market, _amountToBorrow, _shares, address(this));

        // Check if borrower is insolvent (AKA they have bad LTV), revert if they are
        if (minimumHealthFactor > (_getHealthFactor(_id, market))) {
            revert MorphoBlueCollateralAdaptor__HealthFactorTooLow(_id);
        }
    }

    // `repayDebt`

    /**
     * @notice Allows strategists to repay loan debt on Morph Blue Lending Market. Make sure to call addInterest() beforehand to ensure we are repaying what is required.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * TODO: EIN THIS IS WHERE YOU LEFT OFF ON ROUGH IMPLEMENTATION
     */
    function RepayMorphoBlueDebt(Id _id, uint256 _debtTokenRepayAmount) public {
        _validateMBMarket(_id);

        MarketParams memory market = morphoBlue.idToMarketParams(id);
        ERC20 tokenToRepay = ERC20(market.loanToken());

        ERC20 tokenToRepay = ERC20(_fraxlendPairAsset(_fraxlendPair));
        uint256 debtAmountToRepay = _maxAvailable(tokenToRepay, _debtTokenRepayAmount);

        // using Morpho sharesLibrary we can calculate the sharesToRepay from the debtAmount
        uint256 totalBorrowAssets = morphoBlue.market(id).totalBorrowAssets;
                uint256 totalBorrowShares= morphoBlue.market(id).totalBorrowShares;

        uint256 sharesToRepay = debtAmountToRepay.toSharesUp(debtAmountToRepay,totalBorrowAssets ,totalBorrowShares); // get the total assets and total borrow shares of the market
        // TODO - check that Morpho Blue reverts if the repayment amount exceeds the amount of debt the user even has.
        // TODO - check if Morpho Blue reverts if there is no debt.

        // take the smaller btw sharesToRepay and sharesAccToFraxlend
        tokenToRepay.safeApprove(address(_fraxlendPair), type(uint256).max);

        // TODO - EIN - this is where you left off for the night. Just gotta find the mutative function calls in morpho blue to repay the asset.
        // _repayAsset(_fraxlendPair, sharesToRepay);

        // _revokeExternalApproval(tokenToRepay, address(_fraxlendPair));
    }

    /**
     * @notice Allows a strategist to call `accrueInterest()` on a MB Market cellar is using.
     * @dev A strategist might want to do this if a MB market has not been interacted with
     *      in a while, and the strategist does not plan on interacting with it during a
     *      rebalance.
     * @dev Calling this can increase the share price during the rebalance,
     *      so a strategist should consider moving some assets into reserves.
     */
    function accrueInterest(Id id) public {
        _validateMBMarket(id);
        MarketParams memory market = morphoBlue.idToMarketParams(id);
        _accrueInterest(market);
    }

    //============================================ Helper Functions ===========================================

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

    //============================== Interface Details ==============================
    // General message on interface and virtual functions below: The Morpho Blue protocol is meant to be a primitive layer to DeFi, and so other projects may build atop of MB. These possible future projects may implement the same interface to simply interact with MB, and thus this adaptor is implementing a design that allows for future adaptors to simply inherit this "Base Morpho Adaptor" and override what they need appropriately to work with whatever project. Aspects that may be adjusted include using the flexible `bytes` param within `morphoBlue.supplyCollateral()` for example.

    // Current versions in use are just for the primitive Morpho Blue deployments.
    // IMPORTANT: Going forward, other versions will be renamed w/ descriptive titles for new projects extending off of these primitive contracts.
    //===============================================================================

    /**
     * @notice Repay Morpho Blue debt by an amount
     */
    function _repayAsset(MarketParams _market, uint256 _assets, uint256 _sharesToRepay, address _onBehalf) internal virtual {
        morphoBlue.repay(_market, _assets, _sharesToRepay, _onBehalf, bytes memory);
    }
}
