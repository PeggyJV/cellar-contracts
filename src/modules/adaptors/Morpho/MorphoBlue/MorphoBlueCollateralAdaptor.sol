// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { MorphoBlueHelperLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHelperLogic.sol";
import { IMorpho, MarketParams, Id } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";

/**
 * @title Morpho Blue Collateral Adaptor
 * @notice Allows addition and removal of collateralAssets to Morpho Blue pairs for a Cellar.
 * @dev This adaptor is specifically for Morpho Blue Primitive contracts.
 *      To interact with a different version or custom market, a new
 *      adaptor will inherit from this adaptor
 *      and override the interface helper functions. MB refers to Morpho
 *      Blue throughout code.
 * @author 0xEinCodes, crispymangoes
 */
contract MorphoBlueCollateralAdaptor is BaseAdaptor, MorphoBlueHelperLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(Id id)
    // Where:
    // `id` is the var defined by Morpho Blue for the bytes identifier of a Morpho Blue market
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

    /**
     * @param _morphoBlue immutable Morpho Blue contract (called `Morpho.sol` within Morpho Blue repo).
     * @param _healthFactor Minimum Health Factor that replaces minimumHealthFactor. If using new _healthFactor, it must be greater than minimumHealthFactor. See `BaseAdaptor.sol`.
     */
    constructor(address _morphoBlue, uint256 _healthFactor) MorphoBlueHelperLogic(_morphoBlue) {
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
     * @notice User deposits collateralToken to Morpho Blue market.
     * @param assets the amount of assets to provide as collateral on Morpho Blue.
     * @param adaptorData adaptor data containing the abi encoded Id for specific Morpho Blue Lending Market.
     * @dev configurationData is NOT used.
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Morpho Blue.
        Id id = abi.decode(adaptorData, (Id));
        _validateMBMarket(id);
        MarketParams memory market = morphoBlue.idToMarketParams(id);
        ERC20 collateralToken = ERC20(market.collateralToken);
        _addCollateral(market, assets, collateralToken);
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
     * @notice Returns the cellar's balance of the collateralAsset position in corresponding Morpho Blue market.
     * @param adaptorData containing the abi encoded Morpho Blue market Id.
     * @return Cellar's balance of provided collateral to specified MB market.
     * @dev normal static call, thus msg.sender for most-likely Sommelier usecase is the calling cellar.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        Id id = abi.decode(adaptorData, (Id));
        return _userCollateralBalance(id, msg.sender);
    }

    /**
     * @notice Returns collateral asset.
     * @param adaptorData containing the abi encoded Morpho Blue market Id.
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
     * @param _id identifier of a Morpho Blue market.
     * @param _collateralToDeposit The amount of `collateralToken` to add to specified MB market position.
     */
    function addCollateral(Id _id, uint256 _collateralToDeposit) public {
        _validateMBMarket(_id);
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        ERC20 collateralToken = ERC20(market.collateralToken);
        uint256 amountToDeposit = _maxAvailable(collateralToken, _collateralToDeposit);
        _addCollateral(market, amountToDeposit, collateralToken);
    }

    /**
     * @notice Allows strategists to remove collateral from the respective cellar position on specified MB Market.
     * @param _id identifier of a Morpho Blue market.
     * @param _collateralAmount The amount of collateral to remove from specified MB market position.
     */
    function removeCollateral(Id _id, uint256 _collateralAmount) public {
        _validateMBMarket(_id);
        MarketParams memory market = morphoBlue.idToMarketParams(_id);
        if (_collateralAmount == type(uint256).max) {
            _collateralAmount = _userCollateralBalance(_id, address(this));
        }
        _removeCollateral(market, _collateralAmount);
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
     * @param _id identifier of a Morpho Blue market.
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
     * @param _id identifier of a Morpho Blue market.
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
    function _addCollateral(MarketParams memory _market, uint256 _assets, ERC20 _collateralToken) internal virtual {
        // pass in collateralToken because we check maxAvailable beforehand to get assets, then approve ERC20
        _collateralToken.safeApprove(address(morphoBlue), _assets);
        morphoBlue.supplyCollateral(_market, _assets, address(this), hex"");
        // Zero out approvals if necessary.
        _revokeExternalApproval(_collateralToken, address(morphoBlue));
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
