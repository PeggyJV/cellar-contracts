// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorpho } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { MorphoBalancesLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/periphery/MorphoBalancesLib.sol";
import { MorphoLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/periphery/MorphoLib.sol"; // NOTE: not sure I need this yet
import { MorphoBlueHealthFactorLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHealthFactorLogic.sol";

/**
 * @title Morpho Blue Supply Adaptor
 *  * @notice Allows Cellars to lend loanToken to respective Morpho Blue Lending Markets.
 * @dev This adaptor is specifically for Morpho Blue Primitive contracts.
 *      To interact with a different version or custom market, a new
 *      adaptor will inherit from this adaptor
 *      and override the interface helper functions. MB refers to Morpho
 *      Blue
 * @author crispymangoes, 0xEinCodes
 */
contract MorphoBlueSupplyAdaptor is BaseAdaptor, MorphoBlueHealthFactorLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(MarketParams marketParams)
    // Where:
    // `marketParams` is the  struct this adaptor is working with.
    // TODO: Question for Morpho --> should we actually use `bytes32 Id` for the adaptorData? I think we should. It is used as bytes32 within Morpho, but I think it's just ID. So if we pass in bytes32 Id, decode that, then pass it into the functions we should access what we need from Morpho. Talk to Crispy on it, but could just test/try compiling and see what works.
    // More design notes: MorphoBalancesLib, MorphoLib, MorphoStorageLib are periphery contrats with getters for integration. There may be useful things from it.
    // Questions: 1. From `MorphoBalancesLib.sol` it seems that balances can be obtained that have latest accruedInterest applied except for total borrow shares (and it doesn't have interest accrual applied to it anyways). This makes sense bc underlying borrow amounts are increased, and supply assets, not share amounts.
    // NOTE - if we have a cellar as the fee_recipient for a morpho market, then we cannot use some of the getters within the periphery contracts as outlined in their natspec.
    // Referencing `MorphoBalancesLibTest.t.sol` from Morpho Blue codebase to use `MorphoBalancesLib.sol` for exposed getters for morpho blue markets (for user and in total)
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

    constructor(bool _accountForInterest, address _morphoBlue) MorphoBlueHealthFactorLogic(morphoBlue) {
        ACCOUNT_FOR_INTEREST = _accountForInterest;
        morphoBlue = IMorpho(_morphoBlue);
    }

    // ============================================ Global Functions ===========================================
    /**
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
     * @notice Allows user, if Cellar has a MBSupplyAdaptorPosition as its holding position, to deposit into MB markets.
     * @dev Cellar must approve Morpho Blue to spend its assets, then call deposit to lend its assets.
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
        _withdraw(market, assets, receiver, address(this)); // TODO: likely don't need _onBehalf
    }

    /**
     * @notice Returns the amount of loanToken that can be withdrawn.
     * @dev Compares loanToken supplied to loanToken borrowed to check for liquidity.
     *      - If loanToken balance is greater than liquidity available, it returns the amount available.
     * @param adaptorData encoded bytes32 MB id that represents the MB market for this position.
     * @return withdrawableSupply liquid amount of `loanToken` cellar has lent to specified MB market.
     * TODO - this uses periphery libraries that sim expected interest, do we want to use the alternative method which means calling getters within Morpho.sol directly? This would depend on having `accrueInterest()` called by us prior to calling this or called by some other market participant.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory
    ) public view override returns (uint256 withdrawableSupply) {
        Id id = abi.decode(adaptorData, (Id));
        MarketParams memory market = morphoBlue.idToMarketParams(id);
        (uint256 totalSupplyAssets, , uint256 totalBorrowAssets, ) = morphoBlue.expectedMarketBalances(
            morphoBlue,
            market
        );
        if (totalBorrowAssets >= totalSupplyAssets) return 0;
        uint256 liquidSupply = totalSupplyAssets - totalBorrowAssets;
        uint256 cellarSuppliedBalance = morphoBlue.expectedSupplyAssets(morphoBlue, market, msg.sender);
        withdrawableSupply = cellarSuppliedBalance > liquidSupply ? liquidSupply : cellarSuppliedBalance;
    }

    /**
     * @notice Returns the cellar's balance of the supplyToken position.
     * @param adaptorData encoded bytes32 MB id that represents the MB market for this position.
     * @return Cellar's balance of the supplyToken position.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        Id id = abi.decode(adaptorData, (Id));
        MarketParams memory market = morphoBlue.idToMarketParams(id);
        return _balanceOf(market, msg.sender); // TODO maybe reduce to just 1 param (lose the `user` param)
    }

    /**
     * @notice Returns loanToken.
     * @return ERC20 loanToken.
     */
    function assetOf(bytes memory _id) public view override returns (ERC20) {
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        return ERC20(market.loanToken);
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     * @return Whether or not this position is a debt position
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

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
    // General message on interface and virtual functions below: The Morpho Blue protocol is meant to be a primitive layer to DeFi, and so other projects may build atop of MB. These possible future projects may implement the same interface to simply interact with MB, and thus this adaptor is implementing a design that allows for future adaptors to simply inherit this "Base Morpho Adaptor" and override what they need appropriately to work with whatever project. Aspects that may be adjusted include using the flexible `bytes` param within `morphoBlue.supplyCollateral()` for example.

    // Current versions in use are just for the primitive Morpho Blue deployments.
    // IMPORTANT: Going forward, other versions will be renamed w/ descriptive titles for new projects extending off of these primitive contracts.
    //===============================================================================

    /**
     * @notice Deposit loanToken into specified MB lending market.
     * @param _market The specified MB market.
     * @param _assets The amount of `loanToken` to transfer to MB market.
     * @param _onBehalf The address that MB market records as having supplied this amount of `loanToken` as a lender.
     */
    function _deposit(MarketParams _market, uint256 _assets, address _onBehalf) internal virtual {
        morphoBlue.supply(_market, _assets, 0, _onBehalf, bytes(0));
    }

    /**
     * @notice Withdraw loanToken into specified MB lending market.
     * @param _market The specified MB Market
     * @param _assets The amount to withdraw
     * @param _onBehalf The address to which the Asset Tokens will be transferred
     */
    function _withdraw(MarketParams _market, uint256 _assets, uint256 _shares, address _onBehalf) internal virtual {
        morphoBlue.withdraw(_market, _assets, _shares, _onBehalf, _onBehalf);
    }

    /**
     * @dev Returns the amount of tokens owned by `account`.
     * @param _market The specified MB Market
     * @return The expected balance of `loanToken` according to MB Market accounting supplied by this Cellar position, including accrued interest.
     */
    function _balanceOf(MarketParams _market) internal view virtual returns (uint256) {
        return morphoBlue.expectedSupplyAssets(morphoBlue, _market, msg.sender); // TODO - alternatively we call accrueInterest before calling `balanceOf` - the main reason to do this is because `expectedSupplyAssets` is just a simulation, that is likely right, but it is not directly what is actually within the MorphoBlue contracts as state for cellar's position.
    }
}
