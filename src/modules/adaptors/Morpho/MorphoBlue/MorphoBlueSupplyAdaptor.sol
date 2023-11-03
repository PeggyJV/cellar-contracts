// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorpho } from "src/interfaces/external/Morpho/Morpho Blue/IMorpho.sol";

/**
 * @title Morpho Blue Supply Adaptor
 * @dev This adaptor is specifically for Morpho Blue Primitive contracts.
 *      To interact with a different version or custom market, a new
 *      adaptor will inherit from this adaptor
 *      and override the interface helper functions. MB refers to Morpho
 *      Blue
 * @notice Allows Cellars to lend loanToken to respective Morpho Blue Lending Markets.
 * @author crispymangoes, 0xEinCodes
 * THIS IS STILL A ROUGH WIP FULL OF TODO's, but is conceptual at least at a high-level architecture along other Morpho Blue Adaptors.
 */
contract MorphoBlueSupplyAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    type Id is bytes32;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(MarketParams marketParams)
    // Where:
    // `marketParams` is the  struct this adaptor is working with.
    // TODO: Question for Morpho --> should we actually use `bytes32 Id` for the adaptorData?
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    IMorpho public morphoBlue;

    /**
     * @notice Attempted to interact with a Morpho Blue Lending Market that the Cellar is not using.
     */
    error MorphoBlueSupplyAdaptor__MarketPositionsMustBeTracked(Id id);

    /**
     * @notice This bool determines how this adaptor accounts for interest.
     *         True: Account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     *         False: Do not account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     */
    bool public immutable ACCOUNT_FOR_INTEREST;

    constructor(bool _accountForInterest, address _morphoBlue) {
        ACCOUNT_FOR_INTEREST = _accountForInterest;
        morphoBlue = IMorpho(_morphoBlue);
    }

    // ============================================ Global Functions ===========================================
    /**
     * TODO: this is where I left off. EIN - I'd like to set up the basic skeleton for me to pick up again for Morpho Blue.
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Morpho Blue Supply Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Morpho Blue to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Morpho Blue
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market Id
     * @dev configurationData is NOT used
     * TODO: for adaptorData, see TODO at start of contract. Once that's sorted adjust rest of code as needed.
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Morpho Blue.
        Id id = abi.decode(adaptorData, (Id));
        _validateMBMarket(id);

        MarketParams memory market = morphoBlue.idToMarketParams(id);
        // (address _loanToken, , , ) = morphoBlue.idToMarketParams(id); // See IMorpho for `idToMarketParams` and uncomment this if we go with the conventional IMorphoBlue interface function
        ERC20 loanToken = ERC20(market.loanToken);
        loanToken.safeApprove(address(morphoBlue), assets);
        _deposit(market, loanToken, assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(loanToken, address(morphoBlue));
    }

    /**
     * @notice Cellars must withdraw from Morpho Blue lending market, then transfer assets to receiver.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Morpho Blue lending market
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded Id
     * @dev configurationData is NOT used
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Withdraw assets from Morpho Blue.
        Id id = abi.decode(adaptorData, (Id));
        _validateMBMarket(id);
        MarketParams memory market = morphoBlue.idToMarketParams(id);
        _withdraw(market, loanToken, assets, receiver, address(this)); // TODO: likely don't need _onBehalf
    }

    /**
     * @notice Returns the amount of loanToken that can be withdrawn.
     * @dev Compares loanToken supplied to loanToken borrowed to check for liquidity.
     *      - If loanToken balance is greater than liquidity available, it returns the amount available.
     * TODO: this code is from Fraxlend adaptor, but hopefully something similar can work with Morpho Blue
     */
    // function withdrawableFrom(
    //     bytes memory adaptorData,
    //     bytes memory
    // ) public view override returns (uint256 withdrawableFrax) {
    //     IFToken fToken = abi.decode(adaptorData, (IFToken));
    //     (uint128 totalFraxSupplied, , uint128 totalFraxBorrowed, , ) = _getPairAccounting(fToken);
    //     if (totalFraxBorrowed >= totalFraxSupplied) return 0;
    //     uint256 liquidFrax = totalFraxSupplied - totalFraxBorrowed;
    //     uint256 fraxBalance = _toAssetAmount(fToken, _balanceOf(fToken, msg.sender), false, ACCOUNT_FOR_INTEREST);
    //     withdrawableFrax = fraxBalance > liquidFrax ? liquidFrax : fraxBalance;
    // }

    /**
     * @notice Returns the cellar's balance of the loanToken position.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // IFToken fToken = abi.decode(adaptorData, (IFToken));
        // return _toAssetAmount(fToken, _balanceOf(fToken, msg.sender), false, ACCOUNT_FOR_INTEREST);
    }

    /**
     * @notice Returns loanToken.
     */
    function assetOf(bytes memory _id) public view override returns (ERC20) {
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        return ERC20(market.loanToken);
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    // /**
    //  * @notice Allows a strategist to call `addInterest` on a Frax Pair they are using.
    //  * @dev A strategist might want to do this if a Frax Lend pair has not been interacted
    //  *      in a while, and the strategist does not plan on interacting with it during a
    //  *      rebalance.
    //  * @dev Calling this can increase the share price during the rebalance,
    //  *      so a strategist should consider moving some assets into reserves.
    //  */
    // function callAddInterest(IFToken fToken) public {
    //     _validateFToken(fToken);
    //     _addInterest(fToken);
    // }

    /**
     * @notice Validates that a given Id is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateMBMarket(Id _id) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_id)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert MorphoBlueSupplyAdaptor__MarketPositionsMustBeTracked(_id);
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // The Frax Pair interface can slightly change between versions.
    // To account for this, FTokenAdaptors will use the below internal functions when
    // interacting with Frax Pairs, this way new pairs can be added by creating a
    // new contract that inherits from this one, and overrides any function it needs
    // so it conforms with the new Frax Pair interface.

    // Current versions in use for `FraxLendPair` include v1 and v2.

    // IMPORTANT: This `FTokenAdaptor.sol` is associated to the v2 version of `FraxLendPair`
    // whereas FTokenAdaptorV1 is actually associated to `FraxLendPairv1`.
    // The reasoning to name it like this was to set up the base FTokenAdaptor for the
    // most current version, v2. This is in anticipation that more FraxLendPairs will
    // be deployed following v2 in the near future. When later versions are deployed,
    // then the described inheritance pattern above will be used.
    //===============================================================================

    /**
     * @notice Deposit loanToken into specified Morpho Blue lending market
     * @dev ftoken.deposit() calls into the respective version (v2 by default) of FraxLendPair
     * @param fToken The specified FraxLendPair
     * @param amount The amount of $FRAX Token to transfer to Pair
     * @param receiver The address to receive the Asset Shares (fTokens)
     */
    function _deposit(
        MarketParams _market,
        uint256 _assets,
        uint256 _shares,
        address _onBehalf,
        bytes memory _data
    ) internal virtual {
        morphoBlue.supply(_market, _assets, _shares, _onBehalf, _data);
    }

    /**
     * @notice Withdraw $FRAX from specified 'v2' FraxLendPair
     * @dev ftoken.withdraw() calls into the respective version (v2 by default) of FraxLendPair
     * @param fToken The specified FraxLendPair
     * @param assets The amount to withdraw
     * @param receiver The address to which the Asset Tokens will be transferred
     * @param owner The owner of the Asset Shares (fTokens)
     * TODO: likely don't need _onBehalf
     */
    function _withdraw(
        MarketParams _market,
        uint256 _assets,
        uint256 _shares,
        address _onBehalf,
        address _receiver
    ) internal virtual {
        morphoBlue.withdraw(_market, _assets, _shares, _onBehalf, _receiver);
    }

    // /**
    //  * @notice Converts a given number of shares to $FRAX amount from specified 'v2' FraxLendPair
    //  * @dev This is one of the adjusted functions from v1 to v2. ftoken.toAssetAmount() calls into the respective version (v2 by default) of FraxLendPair
    //  * @param fToken The specified FraxLendPair
    //  * @param shares Shares of asset (fToken)
    //  * @param roundUp Whether to round up after division
    //  * @param previewInterest Whether to preview interest accrual before calculation
    //  *      * TODO: most likely don't need an internal function like this to work with Morpho Blue. This was from Fraxlend adaptor work. Will explore more when we look to develop this more.

    //  */
    // function _toAssetAmount(
    //     IFToken fToken,
    //     uint256 shares,
    //     bool roundUp,
    //     bool previewInterest
    // ) internal view virtual returns (uint256) {
    //     return fToken.toAssetAmount(shares, roundUp, previewInterest);
    // }

    /**
     * @dev Returns the amount of tokens owned by `account`.
     * TODO: most likely don't need an internal function like this to work with Morpho Blue. This was from Fraxlend adaptor work. Will explore more when we look to develop this more.
     */
    function _balanceOf(IFToken fToken, address user) internal view virtual returns (uint256) {
        // return fToken.balanceOf(user);
    }

    // /**
    //  * @notice gets all pair level accounting numbers from specified 'v2' FraxLendPair
    //  * @param fToken The specified FraxLendPair
    //  * @return totalAssetAmount Total assets deposited and interest accrued, total claims
    //  * @return totalAssetShares Total fTokens
    //  * @return totalBorrowAmount Total borrows
    //  * @return totalBorrowShares Total borrow shares
    //  * @return totalCollateral Total collateral
    //  * TODO: most likely don't need an internal function like this to work with Morpho Blue. This was from Fraxlend adaptor work. Will explore more when we look to develop this more.
    //  */
    // function _getPairAccounting(
    //     IFToken fToken
    // )
    //     internal
    //     view
    //     virtual
    //     returns (
    //         uint128 totalAssetAmount,
    //         uint128 totalAssetShares,
    //         uint128 totalBorrowAmount,
    //         uint128 totalBorrowShares,
    //         uint256 totalCollateral
    //     )
    // {
    //     (totalAssetAmount, totalAssetShares, totalBorrowAmount, totalBorrowShares, totalCollateral) = fToken
    //         .getPairAccounting();
    // }

    // /**
    //  * @notice Caller calls `addInterest` on specified 'v2' FraxLendPair
    //  * @dev ftoken.addInterest() calls into the respective version (v2 by default) of FraxLendPair
    //  * @param fToken The specified FraxLendPair
    //  * TODO: most likely don't need an internal function like this to work with Morpho Blue. This was from Fraxlend adaptor work. Will explore more when we look to develop this more.

    //  */
    // function _addInterest(IFToken fToken) internal virtual {
    //     fToken.addInterest(false);
    // }
}
