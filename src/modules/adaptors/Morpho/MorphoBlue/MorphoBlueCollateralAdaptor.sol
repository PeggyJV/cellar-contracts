// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { MorphoBlueHealthFactorLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHealthFactorLogic.sol";
import { IMorpho, MarketParams, Id } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";

/**
 * @title Morpho Blue Collateral Adaptor
 * @notice Allows addition and removal of collateralAssets to Morpho Blue pairs for a Cellar.
 * @dev This adaptor is specifically for Morpho Blue Primitive contracts.
 *      To interact with a different version or custom market, a new
 *      adaptor will inherit from this adaptor
 *      and override the interface helper functions. MB refers to Morpho
 *      Blue
 * @author crispymangoes, 0xEinCodes
 * TODO - The periphery libraries from MB may be used depending on how much gas they use. For now we will not use them but we will test to see which is more gas efficient.
 */
contract MorphoBlueCollateralAdaptor is BaseAdaptor, MorphoBlueHealthFactorLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(MarketParams marketParams)
    // Where:
    // `marketParams` is the  struct this adaptor is working with.
    // TODO: Question for Morpho --> should we actually use `bytes32 Id` for the adaptorData? See detailed thoughts in MorphoBlueSupplyAdaptor.sol
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted to interact with an Morpho Blue Lending Market the Cellar is not using.
     */
    error MorphoBlueCollateralAdaptor__MarketPositionsMustBeTracked(Id id);

    /**
     * @notice Removal of collateral causes Cellar Health Factor below what is required
     */
    error MorphoBlueCollateralAdaptor__HealthFactorTooLow(Id id);

    /**
     * @notice Minimum Health Factor enforced after every removeCollateral() strategist function call.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(address _morphoBlue, uint256 _healthFactor) MorphoBlueHealthFactorLogic(_morphoBlue) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
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
        return keccak256(abi.encode("Morpho Blue Collateral Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice User deposits collateralToken to Morpho Blue market
     * @param assets the amount of assets to provide as collateral on Morpho Blue
     * @param adaptorData adaptor data containing the abi encoded Id for specific Morpho Blue Lending Market
     * @dev configurationData is NOT used
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Morpho Blue.
        Id id = abi.decode(adaptorData, (Id));
        _validateMBMarket(id);

        MarketParams memory market = morphoBlue.idToMarketParams(id);
        ERC20 collateralToken = ERC20(market.collateralToken);
        collateralToken.safeApprove(address(morphoBlue), assets);

        _addCollateral(market, assets);

        // Zero out approvals if necessary.
        _revokeExternalApproval(collateralToken, address(morphoBlue));
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     * NOTE: collateral withdrawal calls directly from users disallowed for now.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position is a debt position, and user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     * NOTE: collateral withdrawal calls directly from users disallowed for now.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellar's balance of the collateralAsset position.
     * @param adaptorData the collateral asset deposited into Morpho Blue
     * TODO - could use the periphery library `MorphoBalancesLib` to get the expected balance (w/ simulated interest) but for now we just query the getter. We may switch to using the periphery library.
     * @return Cellar's balance of provided collateral to specified MB market.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        Id id = abi.decode(adaptorData, (Id));
        return _userCollateralBalance(id);
    }

    /**
     * @notice Returns collateral asset.
     * @return The collateral asset in ERC20 type.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        Id id = abi.decode(adaptorData, (Id));
        MarketParams memory market = morphoBlue.idToMarketParams(id);
        return ERC20(market.collateralToken);
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
     * @notice Allows strategists to add collateral to the respective cellar position on specified MB Market, enabling borrowing.
     * @param _id encoded bytes32 MB id that represents the MB market for this position.
     * @param _collateralToDeposit The amount of `collateralToken` to add to specified MB market position.
     */
    function addCollateral(Id _id, uint256 _collateralToDeposit) public {
        _validateMBMarket(_id);
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        ERC20 collateralToken = ERC20(market.collateralToken);

        uint256 amountToDeposit = _maxAvailable(collateralToken, _collateralToDeposit);
        address morphoBlueAddress = address(morphoBlue);
        collateralToken.safeApprove(morphoBlueAddress, amountToDeposit);

        _addCollateral(market, amountToDeposit);

        // Zero out approvals if necessary.
        _revokeExternalApproval(collateralToken, morphoBlueAddress);
    }

    /**
     * @notice Allows strategists to remove collateral from the respective cellar position on specified MB Market.
     * @param _id encoded bytes32 MB id that represents the MB market for this position.
     * @param _collateralAmount The amount of collateral to remove from specified MB market position.
     */
    function removeCollateral(Id _id, uint256 _collateralAmount) public {
        _validateMBMarket(_id);
        MarketParams memory market = morphoBlue.idToMarketParams(_id);

        _accrueInterest(market);
        if (_collateralAmount == type(uint256).max) {
            _collateralAmount = _userCollateralBalance(_id);
        } // TODO - EIN - does it revert if the collateral would make the position not healthy?

        // remove collateral
        _removeCollateral(market, _collateralAmount);

        // TODO - might want to check the market to see if it even has a LLTV. If it doesn't, I guess no liquidations can occur?

        // Check if borrower is insolvent (AKA they have bad LTV), revert if they are
        if (minimumHealthFactor > (_getHealthFactor(_id, market))) {
            revert MorphoBlueCollateralAdaptor__HealthFactorTooLow(_id);
        }
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
            revert MorphoBlueCollateralAdaptor__MarketPositionsMustBeTracked(_id);
    }

    //============================== Interface Details ==============================
    // General message on interface and virtual functions below: The Morpho Blue protocol is meant to be a primitive layer to DeFi, and so other projects may build atop of MB. These possible future projects may implement the same interface to simply interact with MB, and thus this adaptor is implementing a design that allows for future adaptors to simply inherit this "Base Morpho Adaptor" and override what they need appropriately to work with whatever project. Aspects that may be adjusted include using the flexible `bytes` param within `morphoBlue.supplyCollateral()` for example.

    // Current versions in use are just for the primitive Morpho Blue deployments.
    // IMPORTANT: Going forward, other versions will be renamed w/ descriptive titles for new projects extending off of these primitive contracts.
    //===============================================================================

    /**
     * @notice Increment collateral amount in cellar account within specified MB Market.
     * @param _market The specified MB market.
     * @param _assets The amount of collateral to add to MB Market position.
     */
    function _addCollateral(MarketParams memory _market, uint256 _assets) internal virtual {
        morphoBlue.supplyCollateral(_market, _assets, address(this), hex"");
    }

    /**
     * @notice Decrement collateral amount in cellar account within Morpho Blue lending market
     * @param _market The specified MB market.
     * @param _assets The amount of collateral to remove from MB Market position.
     */
    function _removeCollateral(MarketParams memory _market, uint256 _assets) internal virtual {
        morphoBlue.withdrawCollateral(_market, _assets, address(this), address(this));
    }
}
